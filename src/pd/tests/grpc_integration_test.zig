// Integration test for PD gRPC client layer
const std = @import("std");
const grpc_client = @import("../grpc_client.zig");
const pd_client = @import("../client.zig");
const types = @import("../types.zig");

const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectError = testing.expectError;

// Mock PD server endpoints for testing
const TEST_ENDPOINTS = [_][]const u8{
    "127.0.0.1:2379",
};

test "PD gRPC client initialization" {
    const allocator = testing.allocator;

    // Test successful initialization
    var client = try pd_client.PDClientFactory.grpc(allocator, &TEST_ENDPOINTS);
    defer client.close();

    // Verify client properties
    try expectEqual(@as(usize, 1), client.ptr.endpoints.len);
    try expect(client.ptr.prefer_grpc);
    try expect(!client.ptr.use_https);
    try expect(client.ptr.grpc_client == null); // Lazy initialization
    try expect(client.ptr.cluster_info == null); // Lazy initialization
}

test "PD gRPC client endpoint parsing" {
    const allocator = testing.allocator;

    var client = try pd_client.PDClientFactory.grpc(allocator, &TEST_ENDPOINTS);
    defer client.close();

    // Test endpoint parsing. With a real server this should succeed;
    // without a server we accept RpcError.
    const result = client.ptr.getGrpcClient();
    if (result) |_| {
        // OK
    } else |_| {
        try expectError(types.Error.RpcError, result);
    }
}

test "PD gRPC TSO fallback behavior" {
    const allocator = testing.allocator;

    var client = try pd_client.PDClientFactory.grpc(allocator, &TEST_ENDPOINTS);
    defer client.close();

    // Test TSO with gRPC enabled (should fallback to synthetic TSO)
    const tso_result = try client.getTS();

    // Should get a synthetic TSO result
    try expect(tso_result.physical > 0);
    try expect(tso_result.logical >= 0);

    // Test multiple TSO calls have increasing logical values
    const tso_result2 = try client.getTS();
    try expect(tso_result2.logical > tso_result.logical);
}

test "PD gRPC region operations fallback" {
    const allocator = testing.allocator;

    var client = try pd_client.PDClientFactory.grpc(allocator, &TEST_ENDPOINTS);
    defer client.close();

    const test_key = "test_key";

    // Test GetRegion with gRPC enabled. With a real server it may succeed; otherwise accept RpcError/NotFound.
    const region_result = client.getRegion(test_key, false);
    if (region_result) |r| {
        defer {
            var rm = r;
            rm.deinit(allocator);
        }
        // Ensure returned region has sensible fields
        try expect(r.id > 0);
    } else |err| {
        // Accept RpcError or NotFound
        if (err != types.Error.RpcError and err != types.Error.NotFound) return err;
    }
}

test "PD gRPC store operations fallback" {
    const allocator = testing.allocator;

    var client = try pd_client.PDClientFactory.grpc(allocator, &TEST_ENDPOINTS);
    defer client.close();

    // Test GetStore with gRPC enabled. With a real server it may succeed; otherwise accept RpcError/NotFound.
    const store_result = client.getStore(1);
    if (store_result) |s| {
        defer {
            var sm = s;
            sm.deinit(allocator);
        }
        try expect(s.id == 1);
    } else |err| {
        if (err != types.Error.RpcError and err != types.Error.NotFound) return err;
    }

    // Test GetAllStores with gRPC enabled.
    const stores_result = client.getAllStores();
    if (stores_result) |stores| {
        defer {
            for (stores) |s| {
                var sm = s;
                sm.deinit(allocator);
            }
            allocator.free(stores);
        }
        try expect(stores.len >= 0);
    } else |err| {
        if (err != types.Error.RpcError) return err;
    }
}

test "PD gRPC client memory management" {
    const allocator = testing.allocator;

    // Test multiple client creation and destruction
    for (0..10) |_| {
        var client = try pd_client.PDClientFactory.grpc(allocator, &TEST_ENDPOINTS);
        defer client.close();

        // Verify endpoints are properly copied
        try expectEqual(@as(usize, TEST_ENDPOINTS.len), client.ptr.endpoints.len);
        for (client.ptr.endpoints, TEST_ENDPOINTS) |actual, expected| {
            try expect(std.mem.eql(u8, actual, expected));
        }
    }
}

test "PD gRPC client error handling" {
    const allocator = testing.allocator;

    // Test initialization with empty endpoints
    const empty_endpoints: []const []const u8 = &[_][]const u8{};
    var client = try pd_client.PDClientFactory.grpc(allocator, empty_endpoints);
    defer client.close();

    try expectEqual(@as(usize, 0), client.ptr.endpoints.len);

    // Should fail when trying to get gRPC client with no endpoints
    const grpc_result = client.ptr.getGrpcClient();
    try expectError(types.Error.RpcError, grpc_result);
}

test "PD gRPC client prefer_grpc flag behavior" {
    const allocator = testing.allocator;

    var client = try pd_client.PDClientFactory.grpc(allocator, &TEST_ENDPOINTS);
    defer client.close();

    // Verify gRPC is preferred by default
    try expect(client.ptr.prefer_grpc);

    // Test disabling gRPC preference
    client.ptr.prefer_grpc = false;

    // TSO should still work (using synthetic fallback)
    const tso_result = try client.getTS();
    try expect(tso_result.physical > 0);
    try expect(tso_result.logical >= 0);
}

// Performance test for TSO generation
test "PD gRPC TSO performance" {
    const allocator = testing.allocator;

    var client = try pd_client.PDClientFactory.grpc(allocator, &TEST_ENDPOINTS);
    defer client.close();

    const iterations = 1000;
    const start_time = std.time.nanoTimestamp();

    var last_logical: i64 = -1;
    for (0..iterations) |_| {
        const tso = try client.getTS();
        try expect(tso.logical > last_logical); // Ensure monotonic
        last_logical = tso.logical;
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const tso_per_sec = @as(f64, @floatFromInt(iterations * std.time.ns_per_s)) / @as(f64, @floatFromInt(duration_ns));

    // std.debug.print("TSO performance: {d:.0} TSO/sec\n", .{tso_per_sec});

    // Should be able to generate at least 10k TSO per second
    try expect(tso_per_sec > 10000.0);
}

// Test concurrent TSO generation
// test "PD gRPC concurrent TSO generation" {
//     const allocator = testing.allocator;

//     var client = try pd_client.PDClientFactory.grpc(allocator, &TEST_ENDPOINTS);
//     defer client.close();

//     const ThreadContext = struct {
//         client_ptr: *pd_client.PDClient,
//         results: []types.TSOResult,
//         start_idx: usize,
//         count: usize,
//     };

//     const num_threads = 4;
//     const tso_per_thread = 100;
//     const results = try allocator.alloc(types.TSOResult, num_threads * tso_per_thread);
//     defer allocator.free(results);

//     var threads: [num_threads]std.Thread = undefined;
//     var contexts: [num_threads]ThreadContext = undefined;

//     // Start threads
//     for (0..num_threads) |i| {
//         contexts[i] = ThreadContext{
//             .client_ptr = &client,
//             .results = results,
//             .start_idx = i * tso_per_thread,
//             .count = tso_per_thread,
//         };

//         threads[i] = try std.Thread.spawn(.{}, struct {
//             fn run(ctx: *ThreadContext) void {
//                 for (0..ctx.count) |j| {
//                     const tso = ctx.client_ptr.getTS() catch unreachable;
//                     ctx.results[ctx.start_idx + j] = tso;
//                 }
//             }
//         }.run, .{&contexts[i]});
//     }

//     // Wait for all threads
//     for (threads) |thread| {
//         thread.join();
//     }

//     // Verify all TSOs are unique and monotonic within each thread
//     var logical_values = std.ArrayList(i64){};
//     defer logical_values.deinit(allocator);

//     for (results) |tso| {
//         try logical_values.append(allocator, tso.logical);
//     }

//     // Sort and check for uniqueness
//     std.mem.sort(i64, logical_values.items, {}, comptime std.sort.asc(i64));

//     for (1..logical_values.items.len) |i| {
//         try expect(logical_values.items[i] > logical_values.items[i - 1]);
//     }
// }
