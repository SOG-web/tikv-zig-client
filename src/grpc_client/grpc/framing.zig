const std = @import("std");

pub const FramingError = error{
    Truncated,
    InvalidLength,
};

// Reasonable guard to avoid absurd allocations when deframing.
// gRPC default max inbound message size is typically 4MB; we allow larger for flexibility.
const MAX_MESSAGE_LEN: usize = 64 * 1024 * 1024; // 64 MiB

// Encode a single gRPC message with 5-byte prefix.
// flag: 0 = uncompressed, 1 = compressed
pub fn frameMessage(allocator: std.mem.Allocator, payload: []const u8, compressed: bool) ![]u8 {
    const out = try allocator.alloc(u8, 5 + payload.len);
    out[0] = if (compressed) 1 else 0;
    // 4-byte big-endian payload length
    std.mem.writeInt(u32, out[1..5], @intCast(payload.len), .big);
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
    const len_usize: usize = @intCast(std.mem.readInt(u32, data[1..5], .big));
    if (len_usize > MAX_MESSAGE_LEN) return FramingError.InvalidLength;
    const total: usize = 5 + len_usize;
    if (data.len < total) return FramingError.Truncated;

    const msg = try allocator.dupe(u8, data[5..total]);
    return .{ .compressed = compressed, .message = msg };
}

// Helper to check if there are extra bytes beyond one message (not expected for unary)
pub fn hasExtra(data: []const u8) bool {
    if (data.len < 5) return false;
    const len_usize: usize = @intCast(std.mem.readInt(u32, data[1..5], .big));
    const total: usize = 5 + len_usize;
    return data.len > total;
}

test "gRPC framing encode/deframe round-trip" {
    const allocator = std.testing.allocator;
    const payload: []const u8 = "hello-grpc";

    const framed = try frameMessage(allocator, payload, true);
    defer allocator.free(framed);

    const d = try deframeMessage(allocator, framed);
    defer allocator.free(d.message);

    try std.testing.expect(d.compressed);
    try std.testing.expect(std.mem.eql(u8, payload, d.message));
    try std.testing.expect(!hasExtra(framed));
}
