const std = @import("std");

pub const FrameType = enum(u8) {
    DATA = 0x0,
    HEADERS = 0x1,
    PRIORITY = 0x2,
    RST_STREAM = 0x3,
    SETTINGS = 0x4,
    PUSH_PROMISE = 0x5,
    PING = 0x6,
    GOAWAY = 0x7,
    WINDOW_UPDATE = 0x8,
    CONTINUATION = 0x9,
};

pub const FrameFlags = struct {
    pub const END_STREAM = 0x1;
    pub const END_HEADERS = 0x4;
    pub const PADDED = 0x8;
    pub const PRIORITY = 0x20;
};

pub const Frame = struct {
    length: u24,
    type: FrameType,
    flags: u8,
    stream_id: u31,
    payload: []u8,

    pub fn init(allocator: std.mem.Allocator) !Frame {
        return Frame{
            .length = 0,
            .type = .DATA,
            .flags = 0,
            .stream_id = 0,
            .payload = try allocator.alloc(u8, 0),
        };
    }

    pub fn deinit(self: *Frame, allocator: std.mem.Allocator) void {
        allocator.free(self.payload);
    }

    pub fn encode(self: Frame, writer: *std.io.Writer) !void {
        try writer.writeInt(u24, self.length, .big);
        try writer.writeInt(u8, @intFromEnum(self.type), .big);
        try writer.writeInt(u8, self.flags, .big);
        try writer.writeInt(u32, self.stream_id, .big);
        try writer.writeAll(self.payload);
    }

    pub fn decode(reader: *std.Io.Reader, allocator: std.mem.Allocator) !Frame {
        var frame = try Frame.init(allocator);

        // Read 24-bit length (3 bytes) using takeInt
        frame.length = try reader.takeInt(u24, .big);

        // Read frame type (1 byte)
        frame.type = @enumFromInt(try reader.takeByte());

        // Read flags (1 byte)
        frame.flags = try reader.takeByte();

        // Read stream ID (4 bytes) using takeInt
        frame.stream_id = @intCast(try reader.takeInt(u32, .big));

        // Allocate payload buffer
        frame.payload = try allocator.alloc(u8, frame.length);

        // Read the payload data using readSliceAll
        try reader.readSliceAll(frame.payload);

        return frame;
    }
};

test "Frame encode/decode round trip" {
    var frame = try Frame.init(std.testing.allocator);
    defer frame.deinit(std.testing.allocator);

    frame.length = 4;
    frame.type = .DATA;
    frame.flags = FrameFlags.END_STREAM;
    frame.stream_id = 1;

    // Free the initial payload and set the test data
    std.testing.allocator.free(frame.payload);
    frame.payload = try std.testing.allocator.dupe(u8, "test");
    frame.length = @intCast(frame.payload.len);

    // Encode to buffer
    var buf: [1024]u8 = undefined;
    var writer = std.io.Writer.fixed(&buf);
    try frame.encode(&writer);
    const encoded = writer.buffered();

    // // Decode from buffer
    var reader = std.Io.Reader.fixed(encoded);
    var decoded = try Frame.decode(&reader, std.testing.allocator);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqual(frame.length, decoded.length);
    try std.testing.expectEqual(frame.type, decoded.type);
    try std.testing.expectEqual(frame.flags, decoded.flags);
    try std.testing.expectEqual(frame.stream_id, decoded.stream_id);
    try std.testing.expectEqualStrings(frame.payload, decoded.payload);
}
