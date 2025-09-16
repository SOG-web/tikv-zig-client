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

//! Oracle interface and timestamp utilities for TiKV transactions.

const std = @import("std");

/// Option represents available options for the Oracle.
pub const Option = struct {
    txn_scope: []const u8,

    pub fn init(txn_scope: []const u8) Option {
        return Option{ .txn_scope = txn_scope };
    }

    pub fn global() Option {
        return Option{ .txn_scope = GLOBAL_TXN_SCOPE };
    }
};

/// Oracle is the interface that provides strictly ascending timestamps.
pub const Oracle = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        getTimestamp: *const fn (ptr: *anyopaque, ctx: std.mem.Allocator, opt: *const Option) anyerror!u64,
        getTimestampAsync: *const fn (ptr: *anyopaque, ctx: std.mem.Allocator, opt: *const Option) anyerror!Future,
        getLowResolutionTimestamp: *const fn (ptr: *anyopaque, ctx: std.mem.Allocator, opt: *const Option) anyerror!u64,
        getLowResolutionTimestampAsync: *const fn (ptr: *anyopaque, ctx: std.mem.Allocator, opt: *const Option) anyerror!Future,
        getStaleTimestamp: *const fn (ptr: *anyopaque, ctx: std.mem.Allocator, txn_scope: []const u8, prev_second: u64) anyerror!u64,
        isExpired: *const fn (ptr: *anyopaque, lock_timestamp: u64, ttl: u64, opt: *const Option) bool,
        untilExpired: *const fn (ptr: *anyopaque, lock_timestamp: u64, ttl: u64, opt: *const Option) i64,
        close: *const fn (ptr: *anyopaque) void,
    };

    pub fn getTimestamp(self: Oracle, ctx: std.mem.Allocator, opt: *const Option) !u64 {
        return self.vtable.getTimestamp(self.ptr, ctx, opt);
    }

    pub fn getTimestampAsync(self: Oracle, ctx: std.mem.Allocator, opt: *const Option) !Future {
        return self.vtable.getTimestampAsync(self.ptr, ctx, opt);
    }

    pub fn getLowResolutionTimestamp(self: Oracle, ctx: std.mem.Allocator, opt: *const Option) !u64 {
        return self.vtable.getLowResolutionTimestamp(self.ptr, ctx, opt);
    }

    pub fn getLowResolutionTimestampAsync(self: Oracle, ctx: std.mem.Allocator, opt: *const Option) !Future {
        return self.vtable.getLowResolutionTimestampAsync(self.ptr, ctx, opt);
    }

    pub fn getStaleTimestamp(self: Oracle, ctx: std.mem.Allocator, txn_scope: []const u8, prev_second: u64) !u64 {
        return self.vtable.getStaleTimestamp(self.ptr, ctx, txn_scope, prev_second);
    }

    pub fn isExpired(self: Oracle, lock_timestamp: u64, ttl: u64, opt: *const Option) bool {
        return self.vtable.isExpired(self.ptr, lock_timestamp, ttl, opt);
    }

    pub fn untilExpired(self: Oracle, lock_timestamp: u64, ttl: u64, opt: *const Option) i64 {
        return self.vtable.untilExpired(self.ptr, lock_timestamp, ttl, opt);
    }

    pub fn close(self: Oracle) void {
        self.vtable.close(self.ptr);
    }
};

/// Future is a future which promises to return a timestamp.
pub const Future = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        wait: *const fn (ptr: *anyopaque) anyerror!u64,
    };

    pub fn wait(self: Future) !u64 {
        return self.vtable.wait(self.ptr);
    }
};

// Constants
const PHYSICAL_SHIFT_BITS = 18;
const LOGICAL_BITS = (1 << PHYSICAL_SHIFT_BITS) - 1;

/// GlobalTxnScope is the default transaction scope for an Oracle service.
pub const GLOBAL_TXN_SCOPE = "global";

/// ComposeTS creates a ts from physical and logical parts.
pub fn composeTS(physical: i64, logical: i64) u64 {
    return @intCast((physical << PHYSICAL_SHIFT_BITS) + logical);
}

/// ExtractPhysical returns a ts's physical part.
pub fn extractPhysical(ts: u64) i64 {
    return @intCast(ts >> PHYSICAL_SHIFT_BITS);
}

/// ExtractLogical return a ts's logical part.
pub fn extractLogical(ts: u64) i64 {
    return @intCast(ts & LOGICAL_BITS);
}

/// GetPhysical returns current physical time in ms (ignores input to avoid Instant API differences).
pub fn getPhysical(t: std.time.Instant) i64 {
    _ = t;
    return std.time.milliTimestamp();
}

/// Convert milliseconds-since-epoch to a TS (physical-only, logical=0).
pub fn msToTS(ms: i64) u64 {
    return composeTS(ms, 0);
}

/// Return the min start_ts for an uncommitted transaction given max time (ms) using current wall clock.
pub fn lowerLimitStartTSFromNow(max_txn_time_use: i64) u64 {
    const now_ms = std.time.milliTimestamp();
    return msToTS(now_ms - max_txn_time_use);
}

test "timestamp composition and extraction" {
    const physical: i64 = 1640995200000; // 2022-01-01 00:00:00 UTC in ms
    const logical: i64 = 42;
    
    const ts = composeTS(physical, logical);
    
    try std.testing.expectEqual(physical, extractPhysical(ts));
    try std.testing.expectEqual(logical, extractLogical(ts));
}

test "time conversion (ms only)" {
    const now_ms = std.time.milliTimestamp();
    const ts = msToTS(now_ms);
    const recovered_ms = extractPhysical(ts);
    const diff_ms = @abs(recovered_ms - now_ms);
    try std.testing.expect(diff_ms <= 1);
}

test "lower limit start ts" {
    const now_ms = std.time.milliTimestamp();
    const max_txn_time = 1000; // 1 second
    const start_ts = lowerLimitStartTSFromNow(max_txn_time);
    const start_ms = extractPhysical(start_ts);
    try std.testing.expect(start_ms <= now_ms);
    try std.testing.expect(@abs((now_ms - start_ms) - max_txn_time) < 20);
}
