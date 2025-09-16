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

// kvrpcpb.pb.zig patch - Do not delete
// const _DescTable_error_union = struct {
//             err_invalid_start_key: @TypeOf(fd(1, .submessage)),
//             err_physical_table_not_exist: @TypeOf(fd(2, .submessage)),
//             err_compact_in_progress: @TypeOf(fd(3, .submessage)),
//             err_too_many_pending_tasks: @TypeOf(fd(4, .submessage)),
//         };

//         pub const _desc_table: _DescTable_error_union = .{
//             .err_invalid_start_key = fd(1, .submessage),
//             .err_physical_table_not_exist = fd(2, .submessage),
//             .err_compact_in_progress = fd(3, .submessage),
//             .err_too_many_pending_tasks = fd(4, .submessage),
//         };
//     };

//     const _DescTable_CompactError = struct {
//         @"error": @TypeOf(fd(null, .{ .oneof = error_union })),
//     };

//     pub const _desc_table: _DescTable_CompactError = .{
//         .@"error" = fd(null, .{ .oneof = error_union }),
//     };

// disaggregated.pb.zig patch - Do not delete
//  const _DescTable_error_union = struct {
//             success: @TypeOf(fd(1, .submessage)),
//             not_owner: @TypeOf(fd(2, .submessage)),
//             conflict: @TypeOf(fd(3, .submessage)),
//         };

//         pub const _desc_table: _DescTable_error_union = .{
//             .success = fd(1, .submessage),
//             .not_owner = fd(2, .submessage),
//             .conflict = fd(3, .submessage),
//         };
//     };
//     const _DescTable_S3LockResult = struct {
//         @"error": @TypeOf(fd(null, .{ .oneof = error_union })),
//     };

//     pub const _desc_table: _DescTable_S3LockResult = .{
//         .@"error" = fd(null, .{ .oneof = error_union }),
//     };
