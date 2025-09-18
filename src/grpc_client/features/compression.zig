const std = @import("std");
const cz = @import("../../deps/zlib.zig");

pub const Compression = struct {
    pub const Algorithm = enum {
        none,
        gzip,
        deflate,
    };

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Compression {
        return .{ .allocator = allocator };
    }

    pub fn compress(self: *Compression, data: []const u8, algorithm: Algorithm) ![]u8 {
        // TODO: consider switching to zlib-ng (zlib-compat) for performance
        switch (algorithm) {
            .none => return self.allocator.dupe(u8, data),
            .gzip => return try cz.gzipCompress(self.allocator, data, 6),
            .deflate => return try cz.zlibCompress(self.allocator, data, 6),
        }
    }

    pub fn decompress(self: *Compression, data: []const u8, algorithm: Algorithm) ![]u8 {
        switch (algorithm) {
            .none => return self.allocator.dupe(u8, data),
            .gzip => return try cz.gzipDecompress(self.allocator, data),
            .deflate => return try cz.zlibDecompress(self.allocator, data),
        }
    }
};

test "Compression none duplicates input" {
    var c = Compression.init(std.testing.allocator);
    const input = "abc123";
    const out = try c.compress(input, .none);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(input, out);

    const back = try c.decompress(input, .none);
    defer std.testing.allocator.free(back);
    try std.testing.expectEqualStrings(input, back);
}

test "Compression gzip round-trip text and binary" {
    var c = Compression.init(std.testing.allocator);

    // Text
    const text = "hello world: gzip";
    const gz = try c.compress(text, .gzip);
    defer std.testing.allocator.free(gz);
    const un = try c.decompress(gz, .gzip);
    defer std.testing.allocator.free(un);
    try std.testing.expectEqualStrings(text, un);

    // Binary deterministic pattern
    const bin = try std.testing.allocator.alloc(u8, 1024);
    defer std.testing.allocator.free(bin);
    for (bin, 0..) |*b, i| b.* = @intCast(i % 251);

    const gz2 = try c.compress(bin, .gzip);
    defer std.testing.allocator.free(gz2);
    const un2 = try c.decompress(gz2, .gzip);
    defer std.testing.allocator.free(un2);
    try std.testing.expectEqualSlices(u8, bin, un2);
}

test "Compression deflate (zlib-wrapped) round-trip text and binary" {
    var c = Compression.init(std.testing.allocator);

    // Text
    const text = "hello world: deflate";
    const df = try c.compress(text, .deflate);
    defer std.testing.allocator.free(df);
    const un = try c.decompress(df, .deflate);
    defer std.testing.allocator.free(un);
    try std.testing.expectEqualStrings(text, un);

    // Binary deterministic pattern
    const bin = try std.testing.allocator.alloc(u8, 2048);
    defer std.testing.allocator.free(bin);
    for (bin, 0..) |*b, i| b.* = @intCast((i * 7) % 253);

    const df2 = try c.compress(bin, .deflate);
    defer std.testing.allocator.free(df2);
    const un2 = try c.decompress(df2, .deflate);
    defer std.testing.allocator.free(un2);
    try std.testing.expectEqualSlices(u8, bin, un2);

    // // std.debug.print("gzip: {} bytes\n", .{bin.len});
    // // std.debug.print("deflate: {} bytes\n", .{df2.len});
}
