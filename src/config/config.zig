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

const std = @import("std");
const client = @import("client.zig");
const security = @import("security.zig");

// Constants
pub const DEF_STORES_REFRESH_INTERVAL = 60;

// Global configuration storage
var global_config: std.atomic.Value(*Config) = std.atomic.Value(*Config).init(undefined);
var global_config_initialized = std.atomic.Value(bool).init(false);

/// Main configuration structure
pub const Config = struct {
    committer_concurrency: u32,
    max_txn_ttl: u64,
    tikv_client: client.TiKVClient,
    security: security.Security,
    pd_client: PDClient,
    pessimistic_txn: PessimisticTxn,
    txn_local_latches: TxnLocalLatches,
    stores_refresh_interval: u64,
    open_tracing_enable: bool,
    path: []const u8,
    enable_forwarding: bool,
    txn_scope: []const u8,
    enable_async_commit: bool,
    enable_1pc: bool,
    
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Config {
        return Config{
            .committer_concurrency = 128,
            .max_txn_ttl = 60 * 60 * 1000, // 1 hour in milliseconds
            .tikv_client = try client.TiKVClient.default(allocator),
            .security = security.Security.default(),
            .pd_client = PDClient.default(),
            .pessimistic_txn = PessimisticTxn.default(),
            .txn_local_latches = TxnLocalLatches.default(),
            .stores_refresh_interval = DEF_STORES_REFRESH_INTERVAL,
            .open_tracing_enable = false,
            .path = "",
            .enable_forwarding = false,
            .txn_scope = "",
            .enable_async_commit = false,
            .enable_1pc = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Config) void {
        self.tikv_client.deinit();
        self.security.deinit();
    }

    pub fn default(allocator: std.mem.Allocator) !Config {
        return init(allocator);
    }
};

/// PD client configuration
pub const PDClient = struct {
    pd_server_timeout: u32, // seconds

    pub fn default() PDClient {
        return PDClient{
            .pd_server_timeout = 3,
        };
    }
};

/// Transaction local latches configuration
pub const TxnLocalLatches = struct {
    enabled: bool,
    capacity: u32,

    pub fn default() TxnLocalLatches {
        return TxnLocalLatches{
            .enabled = false,
            .capacity = 0,
        };
    }

    pub fn validate(self: *const TxnLocalLatches) !void {
        if (self.enabled and self.capacity == 0) {
            return error.InvalidTxnLocalLatchesCapacity;
        }
    }
};

/// Pessimistic transaction configuration
pub const PessimisticTxn = struct {
    max_retry_count: u32,

    pub fn default() PessimisticTxn {
        return PessimisticTxn{
            .max_retry_count = 256,
        };
    }
};

/// Initialize global configuration
pub fn initGlobalConfig(allocator: std.mem.Allocator) !void {
    if (global_config_initialized.load(.acquire)) {
        return; // Already initialized
    }

    const config = try allocator.create(Config);
    config.* = try Config.default(allocator);
    
    global_config.store(config, .release);
    global_config_initialized.store(true, .release);
}

/// Get global configuration
pub fn getGlobalConfig() ?*Config {
    if (!global_config_initialized.load(.acquire)) {
        return null;
    }
    return global_config.load(.acquire);
}

/// Store global configuration
pub fn storeGlobalConfig(config: *Config) void {
    global_config.store(config, .release);
    global_config_initialized.store(true, .release);
}

/// Update global configuration with a function and return restore function
pub fn updateGlobal(allocator: std.mem.Allocator, update_fn: fn(*Config) void) !fn() void {
    const current = getGlobalConfig() orelse return error.ConfigNotInitialized;
    
    // Create a copy of current config
    const backup = try allocator.create(Config);
    backup.* = current.*;
    
    // Apply update
    update_fn(current);
    
    // Return restore function
    const RestoreFn = struct {
        backup_config: *Config,
        
        pub fn restore(self: @This()) void {
            storeGlobalConfig(self.backup_config);
        }
    };
    
    const restore_data = try allocator.create(RestoreFn);
    restore_data.* = RestoreFn{ .backup_config = backup };
    
    return restore_data.restore;
}

/// Get transaction scope from config
pub fn getTxnScopeFromConfig() []const u8 {
    if (getGlobalConfig()) |config| {
        if (config.txn_scope.len > 0) {
            return config.txn_scope;
        }
    }
    
    return "global"; // Default global scope (equivalent to oracle.GlobalTxnScope)
}

/// Parse connection path
/// Path example: tikv://etcd-node1:port,etcd-node2:port?cluster=1&disableGC=false
pub fn parsePath(allocator: std.mem.Allocator, path: []const u8) !struct {
    etcd_addrs: [][]const u8,
    disable_gc: bool,
} {
    // Use arena allocator for temporary allocations to prevent leaks
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temp_allocator = arena.allocator();
    
    const uri = std.Uri.parse(path) catch |err| {
        return err;
    };

    // Check scheme
    if (!std.ascii.eqlIgnoreCase(uri.scheme, "tikv")) {
        return error.InvalidScheme;
    }

    // Parse query parameters
    var disable_gc = false;
    if (uri.query) |query_component| {
        const query = switch (query_component) {
            .percent_encoded => |s| s,
            .raw => |s| s,
        };
        var iter = std.mem.splitSequence(u8, query, "&");
        while (iter.next()) |param| {
            if (std.mem.startsWith(u8, param, "disableGC=")) {
                const value = param[10..]; // Skip "disableGC="
                if (std.ascii.eqlIgnoreCase(value, "true")) {
                    disable_gc = true;
                } else if (std.ascii.eqlIgnoreCase(value, "false")) {
                    disable_gc = false;
                } else if (value.len > 0) {
                    return error.InvalidDisableGCFlag;
                }
            }
        }
    }

    // Parse host addresses - need to reconstruct host:port from URI components
    const host_component = uri.host orelse return error.MissingHost;
    const host_str = switch (host_component) {
        .percent_encoded => |s| s,
        .raw => |s| s,
    };
    
    // Reconstruct full address including port using temp allocator
    const full_host = if (uri.port) |port|
        try std.fmt.allocPrint(temp_allocator, "{s}:{d}", .{ host_str, port })
    else
        try temp_allocator.dupe(u8, host_str);
    
    var addr_list: std.ArrayList([]const u8) = .empty;
    defer addr_list.deinit(allocator);

    var iter = std.mem.splitSequence(u8, full_host, ",");
    while (iter.next()) |addr| {
        const trimmed = std.mem.trim(u8, addr, " \t");
        if (trimmed.len > 0) {
            // Use main allocator for final result
            try addr_list.append(allocator, try allocator.dupe(u8, trimmed));
        }
    }

    return .{
        .etcd_addrs = try addr_list.toOwnedSlice(allocator),
        .disable_gc = disable_gc,
    };
}

// Tests
test "config creation and validation" {
    const allocator = std.testing.allocator;
    
    var config = try Config.default(allocator);
    defer config.deinit();
    
    try std.testing.expect(config.committer_concurrency == 128);
    try std.testing.expect(config.max_txn_ttl == 60 * 60 * 1000);
    
    // Test TiKV client validation
    try config.tikv_client.validate();
    
    // Test invalid grpc connection count
    config.tikv_client.grpc_connection_count = 0;
    try std.testing.expectError(error.InvalidGrpcConnectionCount, config.tikv_client.validate());
}

test "txn local latches validation" {
    var latches = TxnLocalLatches.default();
    try latches.validate(); // Should pass
    
    latches.enabled = true;
    latches.capacity = 0;
    try std.testing.expectError(error.InvalidTxnLocalLatchesCapacity, latches.validate());
    
    latches.capacity = 100;
    try latches.validate(); // Should pass
}

test "path parsing" {
    const allocator = std.testing.allocator;
    
    // Test simple path first
    const simple_result = try parsePath(allocator, "tikv://node1:2379?disableGC=false");
    defer {
        for (simple_result.etcd_addrs) |addr| {
            allocator.free(addr);
        }
        allocator.free(simple_result.etcd_addrs);
    }
    
    try std.testing.expect(simple_result.etcd_addrs.len == 1);
    try std.testing.expectEqualStrings("node1:2379", simple_result.etcd_addrs[0]);
    try std.testing.expect(simple_result.disable_gc == false);
}

test "global config management" {
    const allocator = std.testing.allocator;
    
    // Save current global state
    const was_initialized = global_config_initialized.load(.acquire);
    const old_config = if (was_initialized) global_config.load(.acquire) else null;
    
    // Reset global state for test
    global_config_initialized.store(false, .release);
    
    try initGlobalConfig(allocator);
    
    const config = getGlobalConfig();
    try std.testing.expect(config != null);
    try std.testing.expect(config.?.committer_concurrency == 128);
    
    const txn_scope = getTxnScopeFromConfig();
    try std.testing.expectEqualStrings(txn_scope, "global");
    
    // Clean up test config
    if (getGlobalConfig()) |test_config| {
        test_config.deinit();
        allocator.destroy(test_config);
    }
    
    // Restore original global state
    if (was_initialized and old_config != null) {
        global_config.store(old_config.?, .release);
        global_config_initialized.store(true, .release);
    } else {
        global_config_initialized.store(false, .release);
    }
}
