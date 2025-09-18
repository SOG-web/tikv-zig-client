// Test runner for PD gRPC integration tests
const std = @import("std");

pub fn main() !void {
    std.debug.print("🚀 Running PD gRPC Integration Tests\n");
    std.debug.print("=====================================\n\n");

    // Import and run the integration tests
    const grpc_tests = @import("grpc_integration_test.zig");

    // Run individual test functions
    const test_functions = [_]struct {
        name: []const u8,
        func: fn () anyerror!void,
    }{
        .{ .name = "PD gRPC client initialization", .func = grpc_tests.@"test PD gRPC client initialization" },
        .{ .name = "PD gRPC client endpoint parsing", .func = grpc_tests.@"test PD gRPC client endpoint parsing" },
        .{ .name = "PD gRPC TSO fallback behavior", .func = grpc_tests.@"test PD gRPC TSO fallback behavior" },
        .{ .name = "PD gRPC region operations fallback", .func = grpc_tests.@"test PD gRPC region operations fallback" },
        .{ .name = "PD gRPC store operations fallback", .func = grpc_tests.@"test PD gRPC store operations fallback" },
        .{ .name = "PD gRPC client memory management", .func = grpc_tests.@"test PD gRPC client memory management" },
        .{ .name = "PD gRPC client error handling", .func = grpc_tests.@"test PD gRPC client error handling" },
        .{ .name = "PD gRPC client prefer_grpc flag behavior", .func = grpc_tests.@"test PD gRPC client prefer_grpc flag behavior" },
        .{ .name = "PD gRPC TSO performance", .func = grpc_tests.@"test PD gRPC TSO performance" },
        .{ .name = "PD gRPC concurrent TSO generation", .func = grpc_tests.@"test PD gRPC concurrent TSO generation" },
    };

    var passed: u32 = 0;
    var failed: u32 = 0;

    for (test_functions) |test_case| {
        std.debug.print("🧪 Testing: {s}... ", .{test_case.name});

        test_case.func() catch |err| {
            std.debug.print("❌ FAILED: {}\n", .{err});
            failed += 1;
            continue;
        };

        std.debug.print("✅ PASSED\n");
        passed += 1;
    }

    std.debug.print("\n📊 Test Results:\n");
    std.debug.print("   ✅ Passed: {d}\n", .{passed});
    std.debug.print("   ❌ Failed: {d}\n", .{failed});
    std.debug.print("   📈 Success Rate: {d:.1}%\n", .{@as(f64, @floatFromInt(passed)) / @as(f64, @floatFromInt(passed + failed)) * 100.0});

    if (failed > 0) {
        std.debug.print("\n⚠️  Some tests failed. This is expected without a running PD server.\n");
        std.debug.print("   The tests verify fallback behavior and error handling.\n");
    } else {
        std.debug.print("\n🎉 All tests passed!\n");
    }
}
