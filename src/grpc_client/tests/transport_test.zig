const std = @import("std");
const Transport = @import("../transport.zig").Transport;
const hpack = @import("../http2/hpack.zig");
const http2_frame = @import("../http2/frame.zig");
const framing = @import("../grpc/framing.zig");

// Mock server round trip test for unary
test "unary mock: server replies with pong" {
    const allocator = std.testing.allocator;

    // Start a mock HTTP/2+gRPC server on a fixed local port
    const port: u16 = 50555;
    var server_thread = try std.Thread.spawn(.{}, struct {
        fn run() void {
            const a = allocator;
            const addr = std.net.Address.parseIp("127.0.0.1", port) catch return;
            var listener = std.net.tcpConnectToAddress(addr) catch return;

            defer listener.close();

            // Read client preface
            var preface_buf: [24]u8 = undefined;
            var rr = listener.reader(null);
            const r = &rr.file_reader.interface;
            // The HTTP/2 connection preface is 24 bytes
            r.readNoEof(&preface_buf) catch return;

            // Read one SETTINGS frame from client (optional for this mock)
            _ = http2_frame.Frame.decode(r, a) catch |e| switch (e) {
                else => {},
            };

            // Read request HEADERS frame
            var req_headers = http2_frame.Frame.decode(r, a) catch return;
            defer req_headers.deinit(a);
            const sid: u31 = req_headers.stream_id;

            // Read request DATA (gRPC framed request)
            var req_data = http2_frame.Frame.decode(r, a) catch return;
            _ = req_data.payload; // framed
            defer req_data.deinit(a);

            // Send response HEADERS (no END_STREAM)
            var enc = hpack.Encoder.init(a) catch return;
            defer enc.deinit();

            var hdrs = std.StringHashMap([]const u8).init(a);
            defer hdrs.deinit();
            // Minimal response headers (status 200 is typical for gRPC)
            hdrs.put(":status", "200") catch return;
            const enc_bytes = enc.encode(hdrs) catch return;

            var resp_h = http2_frame.Frame.init(a) catch return;
            resp_h.type = .HEADERS;
            resp_h.flags = http2_frame.FrameFlags.END_HEADERS; // not END_STREAM yet
            resp_h.stream_id = sid;
            resp_h.payload = enc_bytes;
            resp_h.length = @intCast(enc_bytes.len);

            var bw = listener.writer(null);
            const w = &bw.interface;
            resp_h.encode(w) catch return;
            w.flush() catch return;
            // payload owned by frame; free on deinit
            resp_h.deinit(a);

            // Prepare gRPC framed response payload: "pong"
            const body = "pong";
            const framed_body = framing.frameMessage(a, body, false) catch return;

            var resp_d = http2_frame.Frame.init(a) catch return;
            resp_d.type = .DATA;
            resp_d.flags = 0; // not end stream
            resp_d.stream_id = sid;
            resp_d.payload = framed_body;
            resp_d.length = @intCast(framed_body.len);
            resp_d.encode(w) catch return;
            w.flush() catch return;
            resp_d.deinit(a);

            // Send trailers: grpc-status: 0 with END_STREAM
            var trailers = std.StringHashMap([]const u8).init(a);
            defer trailers.deinit();
            trailers.put("grpc-status", "0") catch return;
            const enc_tr = enc.encode(trailers) catch return;

            var resp_t = http2_frame.Frame.init(a) catch return;
            resp_t.type = .HEADERS;
            resp_t.flags = http2_frame.FrameFlags.END_HEADERS | http2_frame.FrameFlags.END_STREAM;
            resp_t.stream_id = sid;
            resp_t.payload = enc_tr;
            resp_t.length = @intCast(enc_tr.len);
            resp_t.encode(w) catch return;
            w.flush() catch return;
            resp_t.deinit(a);
        }
    }.run, .{});
    defer server_thread.join();

    // Client side: connect and run unary
    const address = try std.net.Address.parseIp("127.0.0.1", port);
    const stream = try std.net.tcpConnectToAddress(address);
    var t = try Transport.init(allocator, stream);
    defer t.deinit();

    const resp = try t.unary("127.0.0.1:50555", "/test.Service/Ping", "ping", .none, null, null);
    defer allocator.free(resp);
    try std.testing.expectEqualStrings("pong", resp);
}

// Frame encoding helper test
test "writeMessage encodes DATA frame correctly" {
    // Create a test frame directly instead of using Transport
    const test_message = "test";
    const frame = http2_frame.Frame{
        .length = @intCast(test_message.len),
        .type = .DATA,
        .flags = http2_frame.FrameFlags.END_STREAM,
        .stream_id = 1,
        .payload = try std.testing.allocator.dupe(u8, test_message),
    };
    defer std.testing.allocator.free(frame.payload);

    // Encode to buffer
    var buffer: [1024]u8 = undefined;
    const bytes_written = try Transport.encodeFrameToBuffer(frame, &buffer);

    // Expected frame: length=4 (u24), type=0 (DATA), flags=1 (END_STREAM), stream_id=1 (u32), payload="test"
    const expected = [_]u8{
        0x00, 0x00, 0x04, // length (24-bit big-endian)
        0x00, // type (DATA = 0)
        0x01, // flags (END_STREAM = 1)
        0x00, 0x00, 0x00, 0x01, // stream_id (32-bit big-endian)
        't', 'e', 's', 't', // payload
    };

    try std.testing.expectEqual(expected.len, bytes_written.len);
    try std.testing.expectEqualSlices(u8, &expected, bytes_written);
}
