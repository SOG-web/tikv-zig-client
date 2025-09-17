const std = @import("std");

pub const FramingError = error{
    Truncated,
    InvalidLength,
};

// Encode a single gRPC message with 5-byte prefix.
// flag: 0 = uncompressed, 1 = compressed
pub fn frameMessage(allocator: std.mem.Allocator, payload: []const u8, compressed: bool) ![]u8 {
    const out = try allocator.alloc(u8, 5 + payload.len);
    out[0] = if (compressed) 1 else 0;
    // 4-byte big-endian payload length
    const len_u32: u32 = @intCast(payload.len);
    out[1] = @intCast((len_u32 >> 24) & 0xff);
    out[2] = @intCast((len_u32 >> 16) & 0xff);
    out[3] = @intCast((len_u32 >> 8) & 0xff);
    out[4] = @intCast(len_u32 & 0xff);
    std.mem.copyForwards(u8, out[5..], payload);
    return out;
}

pub const Deframed = struct {
    compressed: bool,
    message: []u8,
};

// Decode a single gRPC-framed message from a contiguous buffer.
// Returns owned message bytes.
pub fn deframeMessage(allocator: std.mem.Allocator, data: []const u8) !Deframed {
    if (data.len < 5) return FramingError.Truncated;
    const compressed = data[0] == 1;
    const len_be = (@as(u32, data[1]) << 24) | (@as(u32, data[2]) << 16) | (@as(u32, data[3]) << 8) | @as(u32, data[4]);
    const len_usize: usize = @intCast(len_be);
    const total: usize = 5 + len_usize;
    if (data.len < total) return FramingError.Truncated;

    const msg = try allocator.dupe(u8, data[5..total]);
    return .{ .compressed = compressed, .message = msg };
}

// Helper to check if there are extra bytes beyond one message (not expected for unary)
pub fn hasExtra(data: []const u8) bool {
    if (data.len < 5) return false;
    const len_be = (@as(u32, data[1]) << 24) | (@as(u32, data[2]) << 16) | (@as(u32, data[3]) << 8) | @as(u32, data[4]);
    const len_usize: usize = @intCast(len_be);
    const total: usize = 5 + len_usize;
    return data.len > total;
}

test "gRPC framing encode/deframe round-trip" {
    var allocator = std.testing.allocator;
    const payload = "hello-grpc";

    const framed = try frameMessage(allocator, payload, true);
    defer allocator.free(framed);

    const d = try deframeMessage(allocator, framed);
    defer allocator.free(d.message);

    try std.testing.expectEqual(true, d.compressed);
    try std.testing.expectEqualStrings(payload, d.message);
    try std.testing.expect(!hasExtra(framed));
}
