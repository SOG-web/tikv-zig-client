const std = @import("std");

// Export public modules
pub const error_types = @import("error/mod.zig");
pub const config = @import("config/mod.zig");

pub fn main() !void {
    // Initialize logging
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize global config
    try config.initGlobalConfig(allocator);
    
    std.debug.print("TiKV Client-Zig initialized successfully!\n", .{});
    
    // Example usage
    const global_config = config.getGlobalConfig();
    if (global_config) |cfg| {
        std.debug.print("Committer concurrency: {}\n", .{cfg.committer_concurrency});
        std.debug.print("Max TXN TTL: {}ms\n", .{cfg.max_txn_ttl});
        std.debug.print("TXN scope: {s}\n", .{config.getTxnScopeFromConfig()});
    }
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
