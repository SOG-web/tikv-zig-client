const std = @import("std");
const misc = @import("./misc.zig");

// Execution details data structures and formatting helpers
// Ported from client-go/util/execdetails.go with simplified ownership semantics.
// Durations use nanoseconds (i64) for consistency with std.time; helpers format human-readable strings.

pub const ExecDetails = struct {
    backoff_count: i64 = 0,
    backoff_duration_ns: i64 = 0,
    wait_kv_resp_duration_ns: i64 = 0,
    wait_pd_resp_duration_ns: i64 = 0,
};

pub const CommitDetails = struct {
    get_commit_ts_time_ns: i64 = 0,
    prewrite_time_ns: i64 = 0,
    wait_prewrite_binlog_time_ns: i64 = 0,
    commit_time_ns: i64 = 0,
    local_latch_time_ns: i64 = 0,
    resolve_lock_time_ns: i64 = 0,
    write_keys: i32 = 0,
    write_size: i32 = 0,
    prewrite_region_num: i32 = 0,
    txn_retry: i32 = 0,

    pub fn merge(self: *CommitDetails, other: *const CommitDetails) void {
        self.get_commit_ts_time_ns += other.get_commit_ts_time_ns;
        self.prewrite_time_ns += other.prewrite_time_ns;
        self.wait_prewrite_binlog_time_ns += other.wait_prewrite_binlog_time_ns;
        self.commit_time_ns += other.commit_time_ns;
        self.local_latch_time_ns += other.local_latch_time_ns;
        self.resolve_lock_time_ns += other.resolve_lock_time_ns;
        self.write_keys += other.write_keys;
        self.write_size += other.write_size;
        self.prewrite_region_num += other.prewrite_region_num;
        self.txn_retry += other.txn_retry;
    }

    pub fn clone(self: *const CommitDetails) CommitDetails {
        return self.*;
    }
};

pub const LockKeysDetails = struct {
    total_time_ns: i64 = 0,
    region_num: i32 = 0,
    lock_keys: i32 = 0,
    resolve_lock_time_ns: i64 = 0,
    backoff_time_ns: i64 = 0,
    lock_rpc_time_ns: i64 = 0,
    lock_rpc_count: i64 = 0,
    retry_count: i32 = 0,

    pub fn merge(self: *LockKeysDetails, other: *const LockKeysDetails) void {
        self.total_time_ns += other.total_time_ns;
        self.region_num += other.region_num;
        self.lock_keys += other.lock_keys;
        self.resolve_lock_time_ns += other.resolve_lock_time_ns;
        self.backoff_time_ns += other.backoff_time_ns;
        self.lock_rpc_time_ns += other.lock_rpc_time_ns;
        self.lock_rpc_count += other.lock_rpc_count;
        self.retry_count += 1;
    }

    pub fn clone(self: *const LockKeysDetails) LockKeysDetails {
        return self.*;
    }
};

pub const ScanDetail = struct {
    total_keys: i64 = 0,
    processed_keys: i64 = 0,
    processed_keys_size: i64 = 0,
    rocksdb_delete_skipped_count: u64 = 0,
    rocksdb_key_skipped_count: u64 = 0,
    rocksdb_block_cache_hit_count: u64 = 0,
    rocksdb_block_read_count: u64 = 0,
    rocksdb_block_read_byte: u64 = 0,

    pub fn merge(self: *ScanDetail, other: *const ScanDetail) void {
        self.total_keys += other.total_keys;
        self.processed_keys += other.processed_keys;
        self.processed_keys_size += other.processed_keys_size;
        self.rocksdb_delete_skipped_count += other.rocksdb_delete_skipped_count;
        self.rocksdb_key_skipped_count += other.rocksdb_key_skipped_count;
        self.rocksdb_block_cache_hit_count += other.rocksdb_block_cache_hit_count;
        self.rocksdb_block_read_count += other.rocksdb_block_read_count;
        self.rocksdb_block_read_byte += other.rocksdb_block_read_byte;
    }

    pub fn formatAlloc(self: *const ScanDetail, allocator: std.mem.Allocator) ![]u8 {
        if (self.total_keys == 0 and self.processed_keys == 0 and self.processed_keys_size == 0 and
            self.rocksdb_delete_skipped_count == 0 and self.rocksdb_key_skipped_count == 0 and
            self.rocksdb_block_cache_hit_count == 0 and self.rocksdb_block_read_count == 0 and self.rocksdb_block_read_byte == 0)
        {
            return allocator.alloc(u8, 0);
        }
        return try std.fmt.allocPrint(allocator,
            "scan_detail: {total_process_keys: {d}, total_process_keys_size: {d}, total_keys: {d}, rocksdb: {delete_skipped_count: {d}, key_skipped_count: {d}, block: {cache_hit_count: {d}, read_count: {d}, read_byte: {s}}}}",
            .{
                self.processed_keys,
                self.processed_keys_size,
                self.total_keys,
                self.rocksdb_delete_skipped_count,
                self.rocksdb_key_skipped_count,
                self.rocksdb_block_cache_hit_count,
                self.rocksdb_block_read_count,
                try misc.formatBytesAlloc(allocator, @as(i64, @intCast(self.rocksdb_block_read_byte))),
            },
        );
    }
};

pub const TimeDetail = struct {
    process_time_ns: i64 = 0,
    wait_time_ns: i64 = 0,
    kv_read_wall_time_ms: i64 = 0,

    pub fn formatAlloc(self: *const TimeDetail, allocator: std.mem.Allocator) ![]u8 {
        var parts = std.ArrayList([]const u8).init(allocator);
        defer parts.deinit();
        if (self.process_time_ns > 0) {
            const s = try misc.formatDurationAlloc(allocator, self.process_time_ns);
            try parts.append(try std.fmt.allocPrint(allocator, "total_process_time: {s}", .{s}));
        }
        if (self.wait_time_ns > 0) {
            const s = try misc.formatDurationAlloc(allocator, self.wait_time_ns);
            try parts.append(try std.fmt.allocPrint(allocator, "total_wait_time: {s}", .{s}));
        }
        if (parts.items.len == 0) return allocator.alloc(u8, 0);
        const joined = try std.mem.join(allocator, ", ", parts.items);
        return joined;
    }

    pub fn mergeFromPBMillis(self: *TimeDetail, wait_wall_time_ms: i64, process_wall_time_ms: i64, kv_read_wall_time_ms: i64) void {
        self.wait_time_ns += wait_wall_time_ms * 1_000_000;
        self.process_time_ns += process_wall_time_ms * 1_000_000;
        self.kv_read_wall_time_ms += kv_read_wall_time_ms;
    }
};

// ---- tests ----

test "scan detail merge and format" {
    const gpa = std.testing.allocator;
    var a = ScanDetail{ .processed_keys = 10, .processed_keys_size = 1024, .rocksdb_block_read_byte = 2048 };
    var b = ScanDetail{ .processed_keys = 5, .processed_keys_size = 512, .rocksdb_block_read_byte = 1024 };
    a.merge(&b);
    try std.testing.expectEqual(@as(i64, 15), a.processed_keys);
    const s = try a.formatAlloc(gpa);
    defer gpa.free(s);
    try std.testing.expect(std.mem.indexOf(u8, s, "scan_detail:") != null);
}

test "time detail format" {
    const gpa = std.testing.allocator;
    var t = TimeDetail{ .process_time_ns = 12_345_678, .wait_time_ns = 2_000_000_000 };
    const s = try t.formatAlloc(gpa);
    defer gpa.free(s);
    try std.testing.expect(std.mem.indexOf(u8, s, "total_process_time:") != null);
}
