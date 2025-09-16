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

//! Local Oracle implementation using local time as data source.

const std = @import("std");
const oracle_mod = @import("../oracle.zig");

const Oracle = oracle_mod.Oracle;
const Future = oracle_mod.Future;
const Option = oracle_mod.Option;

/// Local Oracle that uses local time as data source
pub const LocalOracle = struct {
    mutex: std.Thread.Mutex,
    last_timestamp_ts: u64,
    n: u64,
    hook: ?struct {
        current_time: std.time.Instant,
    },

    const Self = @This();

    /// Create a new local oracle
    pub fn init() Self {
        return Self{
            .mutex = std.Thread.Mutex{},
            .last_timestamp_ts = 0,
            .n = 0,
            .hook = null,
        };
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

    // Oracle interface implementations
    fn getTimestamp(ptr: *anyopaque, ctx: std.mem.Allocator, opt: *const Option) anyerror!u64 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        _ = ctx;
        _ = opt;

        self.mutex.lock();
        defer self.mutex.unlock();

        const now_ms: i64 = std.time.milliTimestamp();
        const ts = oracle_mod.msToTS(now_ms);

        if (self.last_timestamp_ts == ts) {
            self.n += 1;
            return ts + self.n;
        }

        self.last_timestamp_ts = ts;
        self.n = 0;
        return ts;
    }

    fn getTimestampAsync(ptr: *anyopaque, ctx: std.mem.Allocator, opt: *const Option) anyerror!Future {
        const self: *Self = @ptrCast(@alignCast(ptr));

        const future_impl = try ctx.create(LocalFuture);
        future_impl.* = LocalFuture{
            .oracle_ptr = self,
            .allocator = ctx,
            .opt = opt.*,
        };

        return Future{
            .ptr = future_impl,
            .vtable = &.{
                .wait = LocalFuture.wait,
            },
        };
    }

    fn getLowResolutionTimestamp(ptr: *anyopaque, ctx: std.mem.Allocator, opt: *const Option) anyerror!u64 {
        return getTimestamp(ptr, ctx, opt);
    }

    fn getLowResolutionTimestampAsync(ptr: *anyopaque, ctx: std.mem.Allocator, opt: *const Option) anyerror!Future {
        return getTimestampAsync(ptr, ctx, opt);
    }

    fn getStaleTimestamp(ptr: *anyopaque, ctx: std.mem.Allocator, txn_scope: []const u8, prev_second: u64) anyerror!u64 {
        _ = ptr;
        _ = ctx;
        _ = txn_scope;

        const now_ms: i64 = std.time.milliTimestamp();
        const stale_ms: i64 = now_ms - @as(i64, @intCast(prev_second)) * 1000;
        return oracle_mod.msToTS(stale_ms);
    }

    fn isExpired(ptr: *anyopaque, lock_timestamp: u64, ttl: u64, opt: *const Option) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));
        _ = self; // silence unused
        _ = opt;

        const now_ms: i64 = std.time.milliTimestamp();
        const lock_ms: i64 = oracle_mod.extractPhysical(lock_timestamp);
        const expire_ms: i64 = lock_ms + @as(i64, @intCast(ttl));
        return now_ms >= expire_ms; // now >= expire
    }

    fn untilExpired(ptr: *anyopaque, lock_timestamp: u64, ttl: u64, opt: *const Option) i64 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        _ = opt;

        const now = if (self.hook) |hook| hook.current_time else std.time.Instant.now() catch return 0;
        const lock_physical = oracle_mod.extractPhysical(lock_timestamp);
        const now_physical = oracle_mod.getPhysical(now);

        return lock_physical + @as(i64, @intCast(ttl)) - now_physical;
    }

    fn close(ptr: *anyopaque) void {
        _ = ptr;
        // Nothing to clean up for local oracle
    }
};

/// Future implementation for local oracle async calls
const LocalFuture = struct {
    oracle_ptr: *LocalOracle,
    allocator: std.mem.Allocator,
    opt: Option,

    fn wait(ptr: *anyopaque) anyerror!u64 {
        const self: *LocalFuture = @ptrCast(@alignCast(ptr));
        defer self.allocator.destroy(self);

        return LocalOracle.getTimestamp(self.oracle_ptr, self.allocator, &self.opt);
    }
};

test "local oracle basic" {
    var local = LocalOracle.init();
    const oracle_impl = local.oracle();
    
    const allocator = std.testing.allocator;
    const opt = Option.global();
    
    const ts1 = try oracle_impl.getTimestamp(allocator, &opt);
    const ts2 = try oracle_impl.getTimestamp(allocator, &opt);
    
    try std.testing.expect(ts2 > ts1);
}
