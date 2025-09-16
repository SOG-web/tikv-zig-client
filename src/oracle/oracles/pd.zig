// Copyright 2021 TiKV Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! PD Oracle implementation using TSO client via FFI.

const std = @import("std");
const oracle_mod = @import("../oracle.zig");
const pd = @import("../../pd/client.zig");

const Oracle = oracle_mod.Oracle;
const Future = oracle_mod.Future;
const Option = oracle_mod.Option;

/// Slow distribution threshold for logging warnings
const SLOW_DIST_MS = 30;

// TODO(cascade): Zig version currently uses PD HTTP client; TSO is a dev-only synthetic
// fallback in `pd/grpc_client.zig` until gRPC TSO is wired. When gRPC TSO is implemented,
// set `prefer_grpc = true` and Oracle/clients will use it transparently.

/// PD Oracle implementation
pub const PdOracle = struct {
    allocator: std.mem.Allocator,
    client: pd.PDClient,
    last_ts_map: std.StringHashMap(*std.atomic.Value(u64)),
    last_arrival_ts_map: std.StringHashMap(*std.atomic.Value(u64)),
    quit_channel: std.Thread.ResetEvent,
    update_thread: ?std.Thread,
    mutex: std.Thread.Mutex,

    const Self = @This();

    /// Create a new PD Oracle with the given TSO client and update interval
    pub fn init(allocator: std.mem.Allocator, client: pd.PDClient, update_interval_ms: u64) !*Self {
        var self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = Self{
            .allocator = allocator,
            .client = client,
            .last_ts_map = std.StringHashMap(*std.atomic.Value(u64)).init(allocator),
            .last_arrival_ts_map = std.StringHashMap(*std.atomic.Value(u64)).init(allocator),
            .quit_channel = std.Thread.ResetEvent{},
            .update_thread = null,
            .mutex = std.Thread.Mutex{},
        };

        // Start background update thread
        self.update_thread = try std.Thread.spawn(.{}, updateTSLoop, .{ self, update_interval_ms });

        // Initialize global txn scope timestamp
        const global_opt = Option.global();
        _ = self.getTimestampInternal(global_opt.txn_scope) catch |err| {
            self.deinit();
            return err;
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        // Signal quit and wait for update thread
        self.quit_channel.set();
        if (self.update_thread) |thread| {
            thread.join();
        }

        // Clean up hash maps
        var ts_iter = self.last_ts_map.iterator();
        while (ts_iter.next()) |entry| {
            self.allocator.destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.last_ts_map.deinit();

        var arrival_iter = self.last_arrival_ts_map.iterator();
        while (arrival_iter.next()) |entry| {
            self.allocator.destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.last_arrival_ts_map.deinit();

        self.allocator.destroy(self);
    }

    /// Convert to Oracle interface
    pub fn oracle(self: *Self) Oracle {
        return Oracle{
            .ptr = self,
            .vtable = &.{
                .getTimestamp = getTimestamp,
                .getTimestampAsync = getTimestampAsync,
                .getLowResolutionTimestamp = getLowResolutionTimestamp,
                .getLowResolutionTimestampAsync = getLowResolutionTimestampAsync,
                .getStaleTimestamp = getStaleTimestamp,
                .isExpired = isExpired,
                .untilExpired = untilExpired,
                .close = close,
            },
        };
    }

    fn updateTSLoop(self: *Self, interval_ms: u64) void {
        const interval_ns = interval_ms * std.time.ns_per_ms;

        while (true) {
            // Wait for interval or quit signal
            var quit_set = true;
            self.quit_channel.timedWait(interval_ns) catch {
                // error.Timeout -> not set
                quit_set = false;
            };
            if (quit_set) break; // Quit signal received

            // Update timestamps for all scopes
            self.mutex.lock();
            defer self.mutex.unlock();

            var iter = self.last_ts_map.iterator();
            while (iter.next()) |entry| {
                const scope = entry.key_ptr.*;
                const ts = self.getTimestampInternal(scope) catch |err| {
                    std.log.err("Failed to update TS for scope {s}: {}", .{ scope, err });
                    continue;
                };
                self.setLastTS(ts, scope);
            }
        }
    }

    fn getTimestampInternal(self: *Self, txn_scope: []const u8) !u64 {
        const start_time = std.time.nanoTimestamp();

        const result = if (std.mem.eql(u8, txn_scope, oracle_mod.GLOBAL_TXN_SCOPE) or txn_scope.len == 0)
            try self.client.getTS()
        else
            try self.client.getLocalTS(txn_scope);

        const end_time = std.time.nanoTimestamp();
        const duration_ms = @divTrunc(end_time - start_time, std.time.ns_per_ms);

        if (duration_ms > SLOW_DIST_MS) {
            std.log.warn("Get timestamp too slow: {}ms", .{duration_ms});
        }

        return oracle_mod.composeTS(result.physical, result.logical);
    }

    fn setLastTS(self: *Self, ts: u64, txn_scope: []const u8) void {
        const scope = if (txn_scope.len == 0) oracle_mod.GLOBAL_TXN_SCOPE else txn_scope;

        self.mutex.lock();
        defer self.mutex.unlock();

        // Get or create atomic value for this scope
        const result = self.last_ts_map.getOrPut(scope) catch return;
        if (!result.found_existing) {
            // Clone the scope string
            const owned_scope = self.allocator.dupe(u8, scope) catch return;
            result.key_ptr.* = owned_scope;

            // Create atomic value
            const atomic_val = self.allocator.create(std.atomic.Value(u64)) catch return;
            atomic_val.* = std.atomic.Value(u64).init(0);
            result.value_ptr.* = atomic_val;
        }

        const atomic_val = result.value_ptr.*;

        // Atomic compare-and-swap to ensure monotonic timestamps
        while (true) {
            const current = atomic_val.load(.acquire);
            if (ts <= current) return;

            if (atomic_val.cmpxchgWeak(current, ts, .release, .acquire) == null) {
                break;
            }
        }

        // Update arrival timestamp
        const arrival_ts = oracle_mod.msToTS(std.time.milliTimestamp());
        self.setLastArrivalTS(arrival_ts, scope);
    }

    fn setLastArrivalTS(self: *Self, ts: u64, txn_scope: []const u8) void {
        const scope = if (txn_scope.len == 0) oracle_mod.GLOBAL_TXN_SCOPE else txn_scope;

        // Get or create atomic value for this scope
        const result = self.last_arrival_ts_map.getOrPut(scope) catch return;
        if (!result.found_existing) {
            // Clone the scope string
            const owned_scope = self.allocator.dupe(u8, scope) catch return;
            result.key_ptr.* = owned_scope;

            // Create atomic value
            const atomic_val = self.allocator.create(std.atomic.Value(u64)) catch return;
            atomic_val.* = std.atomic.Value(u64).init(0);
            result.value_ptr.* = atomic_val;
        }

        const atomic_val = result.value_ptr.*;

        // Atomic compare-and-swap
        while (true) {
            const current = atomic_val.load(.acquire);
            if (ts <= current) return;

            if (atomic_val.cmpxchgWeak(current, ts, .release, .acquire) == null) {
                return;
            }
        }
    }

    fn getLastTS(self: *Self, txn_scope: []const u8) ?u64 {
        const scope = if (txn_scope.len == 0) oracle_mod.GLOBAL_TXN_SCOPE else txn_scope;

        self.mutex.lock();
        defer self.mutex.unlock();

        const atomic_val = self.last_ts_map.get(scope) orelse return null;
        return atomic_val.load(.acquire);
    }

    fn getLastArrivalTS(self: *Self, txn_scope: []const u8) ?u64 {
        const scope = if (txn_scope.len == 0) oracle_mod.GLOBAL_TXN_SCOPE else txn_scope;

        self.mutex.lock();
        defer self.mutex.unlock();

        const atomic_val = self.last_arrival_ts_map.get(scope) orelse return null;
        return atomic_val.load(.acquire);
    }

    // Oracle interface implementations
    fn getTimestamp(ptr: *anyopaque, ctx: std.mem.Allocator, opt: *const Option) anyerror!u64 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        _ = ctx;

        const ts = try self.getTimestampInternal(opt.txn_scope);
        self.setLastTS(ts, opt.txn_scope);
        return ts;
    }

    fn getTimestampAsync(ptr: *anyopaque, ctx: std.mem.Allocator, opt: *const Option) anyerror!Future {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const ts = try self.getTimestampInternal(opt.txn_scope);
        self.setLastTS(ts, opt.txn_scope);

        const future_impl = try ctx.create(TSImmediateFuture);
        future_impl.* = TSImmediateFuture{ .ts = ts, .allocator = ctx };

        return Future{ .ptr = future_impl, .vtable = &.{ .wait = TSImmediateFuture.wait } };
    }

    fn getLowResolutionTimestamp(ptr: *anyopaque, ctx: std.mem.Allocator, opt: *const Option) anyerror!u64 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        _ = ctx;

        return self.getLastTS(opt.txn_scope) orelse error.InvalidTxnScope;
    }

    fn getLowResolutionTimestampAsync(ptr: *anyopaque, ctx: std.mem.Allocator, opt: *const Option) anyerror!Future {
        const self: *Self = @ptrCast(@alignCast(ptr));

        const ts = self.getLastTS(opt.txn_scope) orelse return error.InvalidTxnScope;

        const future_impl = try ctx.create(LowResFutureImpl);
        future_impl.* = LowResFutureImpl{ .ts = ts, .allocator = ctx };

        return Future{ .ptr = future_impl, .vtable = &.{ .wait = LowResFutureImpl.wait } };
    }

    fn getStaleTimestamp(ptr: *anyopaque, ctx: std.mem.Allocator, txn_scope: []const u8, prev_second: u64) anyerror!u64 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        _ = ctx;

        const ts = self.getLastTS(txn_scope) orelse return error.InvalidTxnScope;
        const arrival_ts = self.getLastArrivalTS(txn_scope) orelse return error.InvalidTxnScope;

        const arrival_ms: i64 = oracle_mod.extractPhysical(arrival_ts);
        const physical_ms: i64 = oracle_mod.extractPhysical(ts);
        const physical_unix = @divTrunc(physical_ms, 1000);
        if (physical_unix <= prev_second) {
            return error.InvalidPrevSecond;
        }

        // Calculate stale time
        const now_ms: i64 = std.time.milliTimestamp();
        const target_time_ms: i64 = now_ms - @as(i64, @intCast(prev_second)) * 1000;
        const arrival_diff_ms: i64 = now_ms - arrival_ms;
        const stale_ms: i64 = physical_ms - arrival_diff_ms + (target_time_ms - now_ms);
        return oracle_mod.msToTS(stale_ms);
    }

    fn isExpired(ptr: *anyopaque, lock_timestamp: u64, ttl: u64, opt: *const Option) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));

        const last_ts = self.getLastTS(opt.txn_scope) orelse return true;
        return oracle_mod.extractPhysical(last_ts) >= oracle_mod.extractPhysical(lock_timestamp) + @as(i64, @intCast(ttl));
    }

    fn untilExpired(ptr: *anyopaque, lock_timestamp: u64, ttl: u64, opt: *const Option) i64 {
        const self: *Self = @ptrCast(@alignCast(ptr));

        const last_ts = self.getLastTS(opt.txn_scope) orelse return 0;
        return oracle_mod.extractPhysical(lock_timestamp) + @as(i64, @intCast(ttl)) - oracle_mod.extractPhysical(last_ts);
    }

    fn close(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};

/// Immediate future for getTimestampAsync using PD client
const TSImmediateFuture = struct {
    ts: u64,
    allocator: std.mem.Allocator,

    fn wait(ptr: *anyopaque) anyerror!u64 {
        const self: *TSImmediateFuture = @ptrCast(@alignCast(ptr));
        defer self.allocator.destroy(self);
        return self.ts;
    }
};

/// Future implementation for low resolution timestamps
const LowResFutureImpl = struct {
    ts: u64,
    allocator: std.mem.Allocator,

    fn wait(ptr: *anyopaque) anyerror!u64 {
        const self: *LowResFutureImpl = @ptrCast(@alignCast(ptr));
        defer self.allocator.destroy(self);
        return self.ts;
    }
};

test "timestamp composition" {
    const physical: i64 = 1640995200000;
    const logical: i64 = 42;
    const ts = oracle_mod.composeTS(physical, logical);

    try std.testing.expectEqual(physical, oracle_mod.extractPhysical(ts));
    try std.testing.expectEqual(logical, oracle_mod.extractLogical(ts));
}
