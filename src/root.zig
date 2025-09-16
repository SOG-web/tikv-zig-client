//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
pub const util = @import("util/mod.zig");
pub const examples = @import("examples/mod.zig");
pub const kvproto_header_sanity = @import("kvproto/header_sanity_test.zig");
pub const kvproto_roundtrip = @import("kvproto/roundtrip_test.zig");
pub const kv = @import("kv/mod.zig");
pub const metrics = @import("metrics/mod.zig");
pub const oracle = @import("oracle/mod.zig");
pub const config = @import("config/mod.zig");
pub const errorM = @import("error/mod.zig");
pub const pd = @import("pd/mod.zig");
pub const c = @import("c.zig");
// pub const tikvrpc = @import("tikvrpc/mod.zig");

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}

test "aggregate modules" {
    _ = util;
    _ = config;
    _ = kv;
    _ = metrics;
    _ = errorM;
    _ = kvproto_header_sanity;
    _ = kvproto_roundtrip;
    _ = oracle;
    _ = pd;
    //  _ = tikvrpc;
    _ = c;
}
