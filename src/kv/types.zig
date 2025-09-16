// TiKV client Zig - kv/types (variables, lock ctx, replica read)
const std = @import("std");
const root = @import("root");
const utils = @import("../util/mod.zig");

// ---------------- Variables (from variables.go) ----------------

pub const DefBackoffLockFast: i32 = 10;
pub const DefBackOffWeight: i32 = 2;

pub const Variables = struct {
    // BackoffLockFast specifies the LockFast backoff base duration in milliseconds.
    backoff_lock_fast: i32 = DefBackoffLockFast,
    // BackOffWeight specifies the weight of the max back off time duration.
    back_off_weight: i32 = DefBackOffWeight,
    // Pointer to SessionVars.Killed (flag indicating the query is killed)
    killed: *u32,

    pub fn init(killed: *u32) Variables {
        return .{
            .backoff_lock_fast = DefBackoffLockFast,
            .back_off_weight = DefBackOffWeight,
            .killed = killed,
        };
    }
};

var _ignore_kill: u32 = 0;
pub fn defaultVariables() Variables {
    return Variables.init(&_ignore_kill);
}

// ---------------- Store vars (from store_vars.go) ----------------

pub const ReplicaReadType = enum(u8) {
    Leader = 0,
    Follower = 1,
    Mixed = 2,

    pub fn isFollowerRead(self: ReplicaReadType) bool {
        return self != .Leader;
    }
};

pub const StoreLimit = struct {
    // atomic i64 value
    value: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),

    pub fn load(self: *const StoreLimit) i64 {
        return self.value.load(.seq_cst);
    }

    pub fn store(self: *StoreLimit, v: i64) void {
        self.value.store(v, .seq_cst);
    }
}{}; // allow instantiation

pub var store_limit = StoreLimit{};

// ---------------- ReturnedValue and LockCtx (from kv.go) ----------------

pub const ReturnedValue = struct {
    value: []u8 = &[_]u8{},
    exists: bool = false,
    already_locked: bool = false,
};

pub const PessimisticLockRequest = opaque {};
pub const ErrDeadlock = opaque {};

pub const LockCtx = struct {
    // allocator for owning internal buffers (keys/values in map)
    allocator: std.mem.Allocator,

    killed: *u32 = &_ignore_kill,
    for_update_ts: u64 = 0,
    lock_wait_time_ms: ?i64 = null, // null => default (always wait)
    wait_start_time_ms: i64 = 0,
    pessimistic_lock_waited: *i32 = undefined,
    lock_keys_duration_ms: *i64 = undefined,
    lock_keys_count: *i32 = undefined,

    return_values: bool = false,
    check_existence: bool = false,

    // Map of key -> ReturnedValue. We own both key bytes and value bytes when present.
    values: ?std.StringHashMap(ReturnedValue) = null,
    values_lock: std.Thread.Mutex = .{},

    lock_expired: *u32 = undefined,
    stats: *utils.execdetails.LockKeysDetailsT = undefined,
    resource_group_tag: []u8 = &[_]u8{},
    resource_group_tagger: ?*const fn (*PessimisticLockRequest) []u8 = null,
    on_deadlock: ?*const fn (*ErrDeadlock) void = null,

    pub fn init(allocator: std.mem.Allocator, for_update_ts: u64, lock_wait_time_ms: i64, wait_start_time_ms: i64) LockCtx {
        return .{
            .allocator = allocator,
            .for_update_ts = for_update_ts,
            .lock_wait_time_ms = lock_wait_time_ms,
            .wait_start_time_ms = wait_start_time_ms,
        };
    }

    pub fn lockWaitTime(self: *LockCtx) i64 {
        if (self.lock_wait_time_ms) |v| return v;
        self.lock_wait_time_ms = @as(i64, std.math.maxInt(i64)); // LockAlwaysWait
        return self.lock_wait_time_ms.?;
    }

    pub fn initReturnValues(self: *LockCtx, capacity: usize) !void {
        self.return_values = true;
        if (self.values == null) {
            const map = std.StringHashMap(ReturnedValue).init(self.allocator);
            try map.ensureTotalCapacity(capacity);
            self.values = map;
        }
    }

    pub fn initCheckExistence(self: *LockCtx, capacity: usize) !void {
        self.check_existence = true;
        if (self.values == null) {
            const map = std.StringHashMap(ReturnedValue).init(self.allocator);
            try map.ensureTotalCapacity(capacity);
            self.values = map;
        }
    }

    /// Insert or update a returned value for a key. Duplicates key and value into ctx allocator.
    pub fn setReturnedValue(self: *LockCtx, key: []const u8, val: []const u8, exists: bool, already_locked: bool) !void {
        self.values_lock.lock();
        defer self.values_lock.unlock();
        if (self.values == null) {
            const map = std.StringHashMap(ReturnedValue).init(self.allocator);
            self.values = map;
        }
        var map_ref = &self.values.?;
        // Duplicate key and value to own them.
        const k_copy = try self.allocator.dupe(u8, key);
        const v_copy = try self.allocator.dupe(u8, val);
        const rv = ReturnedValue{ .value = v_copy, .exists = exists, .already_locked = already_locked };
        // Insert: if existing, free old resources and replace.
        if (map_ref.fetchPut(k_copy, rv)) |entry| {
            // Free previous key (owned by map) and value
            self.allocator.free(entry.key_ptr.*);
            if (entry.value_ptr.*.value.len > 0) self.allocator.free(entry.value_ptr.*.value);
            entry.key_ptr.* = k_copy;
            entry.value_ptr.* = rv;
        }
    }

    pub const ValueLookup = struct { value: ?[]const u8, not_locked: bool };

    pub fn getValueNotLocked(self: *LockCtx, key: []const u8) ValueLookup {
        if (self.values) |*m| {
            if (m.get(key)) |rv| {
                if (!rv.already_locked) return .{ .value = rv.value, .not_locked = true };
                return .{ .value = null, .not_locked = false };
            }
        }
        return .{ .value = null, .not_locked = false };
    }

    pub fn iterateValuesNotLocked(self: *LockCtx, f: *const fn ([]const u8, []const u8) void) void {
        self.values_lock.lock();
        defer self.values_lock.unlock();
        if (self.values) |*m| {
            var it = m.iterator();
            while (it.next()) |e| {
                if (!e.value_ptr.*.already_locked) {
                    f(e.key_ptr.*, e.value_ptr.*.value);
                }
            }
        }
    }

    pub fn deinit(self: *LockCtx) void {
        if (self.values) |*m| {
            var it = m.iterator();
            while (it.next()) |e| {
                if (e.key_ptr.*.len > 0) self.allocator.free(e.key_ptr.*);
                if (e.value_ptr.*.value.len > 0) self.allocator.free(e.value_ptr.*.value);
            }
            m.deinit();
            self.values = null;
        }
    }
};

// ---------------- constants from kv.go ----------------

pub const LockAlwaysWait: i64 = std.math.maxInt(i64);
pub const LockNoWait: i64 = -1;

// ---------------- Tests ----------------

test "Variables defaults" {
    const v = defaultVariables();
    try std.testing.expectEqual(DefBackoffLockFast, v.backoff_lock_fast);
    try std.testing.expectEqual(DefBackOffWeight, v.back_off_weight);
}

test "ReplicaReadType follower read" {
    try std.testing.expect(ReplicaReadType.Leader.isFollowerRead() == false);
    try std.testing.expect(ReplicaReadType.Follower.isFollowerRead() == true);
}
