// internal/logutil/hex.zig
// Hex helpers for logging byte slices similar to Go's Hex(proto.Message) which hex-prints []byte fields.
// In Zig we keep it simple: provide a format wrapper for []const u8 that prints as lowercase hex.

const std = @import("std");

pub const HexBytes = struct {
    data: []const u8,

    pub fn format(self: HexBytes, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt; _ = options;
        return std.fmt.format(writer, "{s}", .{ std.fmt.fmtSliceHexLower(self.data) });
    }
};

pub fn hexBytes(b: []const u8) HexBytes {
    return .{ .data = b };
}

test "hexBytes formats to hex" {
    var buf: [64]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const w = fba.writer();
    try std.fmt.format(w, "{}", .{ hexBytes(&[_]u8{0x0a, 0xff}) });
    const s = fba.buffer[0..fba.end_index];
    try std.testing.expect(std.mem.eql(u8, s, "0aff"));
}
