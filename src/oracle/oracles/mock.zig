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

//! Mock Oracle implementation for testing.

const std = @import("std");
const oracle_mod = @import("../oracle.zig");

const Oracle = oracle_mod.Oracle;
const Future = oracle_mod.Future;
const Option = oracle_mod.Option;

const MockError = error{
    Stopped,
};

/// Mock Oracle for testing
pub const MockOracle = struct {
    mutex: std.Thread.RwLock,
    stop: bool,
    offset: i64, // nanoseconds
    last_ts: u64,

    const Self = @This();

    /// Create a new mock oracle
    pub fn init() Self {
        return Self{
            .mutex = std.Thread.RwLock{},
            .stop = false,
            .offset = 0,
            .last_ts = 0,
        };
    }

    /// Enable the oracle
    pub fn enable(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.stop = false;
    }

    /// Disable the oracle
    pub fn disable(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.stop = true;
    }

    /// Add offset to the oracle time
    pub fn addOffset(self: *Self, duration_ns: i64) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.offset += duration_ns;
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

        if (self.stop) {
            return MockError.Stopped;
        }

        const now_ms: i64 = std.time.milliTimestamp();
        const offset_ms: i64 = @divTrunc(self.offset, std.time.ns_per_ms);
        const adjusted_ms: i64 = now_ms + offset_ms;
        const ts = oracle_mod.msToTS(adjusted_ms);
        
        if (oracle_mod.extractPhysical(self.last_ts) == oracle_mod.extractPhysical(ts)) {
            self.last_ts += 1;
        } else {
            self.last_ts = ts;
        }

        return self.last_ts;
    }

    fn getTimestampAsync(ptr: *anyopaque, ctx: std.mem.Allocator, opt: *const Option) anyerror!Future {
        const self: *Self = @ptrCast(@alignCast(ptr));

        const future_impl = try ctx.create(MockFuture);
        future_impl.* = MockFuture{
            .oracle_ptr = self,
            .allocator = ctx,
            .opt = opt.*,
        };

        return Future{
            .ptr = future_impl,
            .vtable = &.{
                .wait = MockFuture.wait,
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
        _ = opt;

        self.mutex.lockShared();
        defer self.mutex.unlockShared();

        const now_ms: i64 = std.time.milliTimestamp();
        const offset_ms: i64 = @divTrunc(self.offset, std.time.ns_per_ms);
        const adjusted_ms: i64 = now_ms + offset_ms;
        const lock_ms: i64 = oracle_mod.extractPhysical(lock_timestamp);
        const expire_ms: i64 = lock_ms + @as(i64, @intCast(ttl));
        return adjusted_ms >= expire_ms;
    }

    fn untilExpired(ptr: *anyopaque, lock_timestamp: u64, ttl: u64, opt: *const Option) i64 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        _ = opt;

        self.mutex.lockShared();
        defer self.mutex.unlockShared();

        const now_ms: i64 = std.time.milliTimestamp();
        const offset_ms: i64 = @divTrunc(self.offset, std.time.ns_per_ms);
        const adjusted_ms: i64 = now_ms + offset_ms;
        const lock_ms: i64 = oracle_mod.extractPhysical(lock_timestamp);
        const expire_ms: i64 = lock_ms + @as(i64, @intCast(ttl));
        if (adjusted_ms >= expire_ms) return 0;
        return @intCast(expire_ms - adjusted_ms);
    }

    fn close(ptr: *anyopaque) void {
        _ = ptr;
        // Nothing to clean up for mock oracle
    }
};

/// Future implementation for mock oracle async calls
const MockFuture = struct {
    oracle_ptr: *MockOracle,
    allocator: std.mem.Allocator,
    opt: Option,

    fn wait(ptr: *anyopaque) anyerror!u64 {
        const self: *MockFuture = @ptrCast(@alignCast(ptr));
        defer self.allocator.destroy(self);

        return MockOracle.getTimestamp(self.oracle_ptr, self.allocator, &self.opt);
    }
};

test "mock oracle basic" {
    var mock = MockOracle.init();
    const oracle_impl = mock.oracle();
    
    const allocator = std.testing.allocator;
    const opt = Option.global();
    
    // Test normal operation
    const ts1 = try oracle_impl.getTimestamp(allocator, &opt);
    const ts2 = try oracle_impl.getTimestamp(allocator, &opt);
    try std.testing.expect(ts2 > ts1);
    
    // Test disable/enable
    mock.disable();
    try std.testing.expectError(MockError.Stopped, oracle_impl.getTimestamp(allocator, &opt));
    
    mock.enable();
    const ts3 = try oracle_impl.getTimestamp(allocator, &opt);
    try std.testing.expect(ts3 > ts2);
}

test "mock oracle offset" {
    var mock = MockOracle.init();
    const oracle_impl = mock.oracle();
    
    const allocator = std.testing.allocator;
    const opt = Option.global();
    
    const ts1 = try oracle_impl.getTimestamp(allocator, &opt);
    
    // Add 1 second offset
    mock.addOffset(std.time.ns_per_s);
    const ts2 = try oracle_impl.getTimestamp(allocator, &opt);
    
    // Should be significantly larger due to offset
    const diff_ms = @divTrunc(oracle_mod.extractPhysical(ts2) - oracle_mod.extractPhysical(ts1), 1);
    try std.testing.expect(diff_ms >= 1000); // At least 1 second difference
}
