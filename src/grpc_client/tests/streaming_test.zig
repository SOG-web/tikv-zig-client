// Tests for streaming gRPC functionality
const std = @import("std");
const http2_integration = @import("../http2_integration.zig");
const frame = @import("../http2/frame.zig");

// Mock HTTP/2 connection for testing
const MockHttp2Connection = struct {
    allocator: std.mem.Allocator,
    sent_frames: std.ArrayList(frame.Frame),
    received_frames: std.ArrayList(frame.Frame),
    
    pub fn init(allocator: std.mem.Allocator) @This() {
        return @This(){
            .allocator = allocator,
            .sent_frames = std.ArrayList(http2.Http2Frame).init(allocator),
            .received_frames = std.ArrayList(http2.Http2Frame).init(allocator),
        };
    }
    
    pub fn deinit(self: *@This()) void {
        for (self.sent_frames.items) |frame| {
            frame.deinit(self.allocator);
        }
        self.sent_frames.deinit();
        
        for (self.received_frames.items) |frame| {
            frame.deinit(self.allocator);
        }
        self.received_frames.deinit();
    }
    
    pub fn sendFrame(self: *@This(), frame: http2.Http2Frame) !void {
        // Deep copy the frame for testing
        const payload_copy = try self.allocator.dupe(u8, frame.payload);
        const frame_copy = http2.Http2Frame{
            .frame_type = frame.frame_type,
            .flags = frame.flags,
            .stream_id = frame.stream_id,
            .payload = payload_copy,
        };
        try self.sent_frames.append(frame_copy);
    }
    
    pub fn receiveFrame(self: *@This()) !http2.Http2Frame {
        if (self.received_frames.items.len == 0) {
            return error.WouldBlock;
        }
        return self.received_frames.orderedRemove(0);
    }
    
    pub fn handleFrame(self: *@This(), frame: http2.Http2Frame) !void {
        // Mock frame handling - just cleanup the frame
        frame.deinit(self.allocator);
    }
    
    // Helper for tests to inject received frames
    pub fn injectFrame(self: *@This(), frame: http2.Http2Frame) !void {
        const payload_copy = try self.allocator.dupe(u8, frame.payload);
        const frame_copy = http2.Http2Frame{
            .frame_type = frame.frame_type,
            .flags = frame.flags,
            .stream_id = frame.stream_id,
            .payload = payload_copy,
        };
        try self.received_frames.append(frame_copy);
    }
};

test "grpc stream creation and initialization" {
    const allocator = std.testing.allocator;
    
    var mock_conn = MockHttp2Connection.init(allocator);
    defer mock_conn.deinit();
    
    var stream = try streaming.GrpcStream.init(
        allocator,
        1,
        .bidirectional_streaming,
        @ptrCast(&mock_conn),
    );
    defer stream.deinit();
    
    try std.testing.expect(stream.stream_id == 1);
    try std.testing.expect(stream.stream_type == .bidirectional_streaming);
    try std.testing.expect(stream.state == .idle);
    try std.testing.expect(stream.local_window == 65535);
    try std.testing.expect(stream.remote_window == 65535);
    try std.testing.expect(!stream.headers_sent);
    try std.testing.expect(!stream.headers_received);
}

test "grpc stream send headers" {
    const allocator = std.testing.allocator;
    
    var mock_conn = MockHttp2Connection.init(allocator);
    defer mock_conn.deinit();
    
    var stream = try streaming.GrpcStream.init(
        allocator,
        1,
        .server_streaming,
        @ptrCast(&mock_conn),
    );
    defer stream.deinit();
    
    const headers = [_]http2.Header{
        .{ .name = ":method", .value = "POST" },
        .{ .name = ":path", .value = "/pdpb.PD/ScanRegions" },
        .{ .name = "content-type", .value = "application/grpc+proto" },
    };
    
    try stream.sendHeaders(&headers);
    
    try std.testing.expect(stream.headers_sent);
    try std.testing.expect(stream.state == .open);
    try std.testing.expect(mock_conn.sent_frames.items.len == 1);
    
    const sent_frame = mock_conn.sent_frames.items[0];
    try std.testing.expect(sent_frame.frame_type == .headers);
    try std.testing.expect(sent_frame.stream_id == 1);
    try std.testing.expect(sent_frame.flags & http2.Http2Frame.FLAG_END_HEADERS != 0);
    try std.testing.expect(sent_frame.flags & http2.Http2Frame.FLAG_END_STREAM == 0); // Not end_stream for streaming
}

test "grpc stream send data with flow control" {
    const allocator = std.testing.allocator;
    
    var mock_conn = MockHttp2Connection.init(allocator);
    defer mock_conn.deinit();
    
    var stream = try streaming.GrpcStream.init(
        allocator,
        1,
        .client_streaming,
        @ptrCast(&mock_conn),
    );
    defer stream.deinit();
    
    // Set stream to open state
    stream.state = .open;
    
    const test_data = "Hello, streaming gRPC!";
    const initial_window = stream.remote_window;
    
    try stream.sendData(test_data, false);
    
    try std.testing.expect(stream.remote_window == initial_window - @as(i32, @intCast(test_data.len)));
    try std.testing.expect(mock_conn.sent_frames.items.len == 1);
    
    const sent_frame = mock_conn.sent_frames.items[0];
    try std.testing.expect(sent_frame.frame_type == .data);
    try std.testing.expect(sent_frame.stream_id == 1);
    try std.testing.expect(sent_frame.flags & http2.Http2Frame.FLAG_END_STREAM == 0);
    try std.testing.expect(std.mem.eql(u8, sent_frame.payload, test_data));
}

test "grpc stream send end stream" {
    const allocator = std.testing.allocator;
    
    var mock_conn = MockHttp2Connection.init(allocator);
    defer mock_conn.deinit();
    
    var stream = try streaming.GrpcStream.init(
        allocator,
        1,
        .client_streaming,
        @ptrCast(&mock_conn),
    );
    defer stream.deinit();
    
    stream.state = .open;
    
    try stream.sendEndStream();
    
    try std.testing.expect(stream.state == .half_closed_local);
    try std.testing.expect(mock_conn.sent_frames.items.len == 1);
    
    const sent_frame = mock_conn.sent_frames.items[0];
    try std.testing.expect(sent_frame.frame_type == .data);
    try std.testing.expect(sent_frame.flags & http2.Http2Frame.FLAG_END_STREAM != 0);
    try std.testing.expect(sent_frame.payload.len == 0); // Empty data frame
}

test "grpc stream receive message" {
    const allocator = std.testing.allocator;
    
    var mock_conn = MockHttp2Connection.init(allocator);
    defer mock_conn.deinit();
    
    var stream = try streaming.GrpcStream.init(
        allocator,
        1,
        .server_streaming,
        @ptrCast(&mock_conn),
    );
    defer stream.deinit();
    
    stream.state = .open;
    stream.headers_received = true;
    
    // Inject a data frame
    const test_message = "Received message from server";
    const data_frame = try http2.Http2Frame.createData(allocator, 1, test_message, false);
    defer data_frame.deinit(allocator);
    
    try mock_conn.injectFrame(data_frame);
    
    const received = try stream.receiveMessage();
    defer if (received) |msg| allocator.free(msg);
    
    try std.testing.expect(received != null);
    try std.testing.expect(std.mem.eql(u8, received.?, test_message));
}

test "grpc stream bidirectional communication" {
    const allocator = std.testing.allocator;
    
    var mock_conn = MockHttp2Connection.init(allocator);
    defer mock_conn.deinit();
    
    var stream = try streaming.GrpcStream.init(
        allocator,
        1,
        .bidirectional_streaming,
        @ptrCast(&mock_conn),
    );
    defer stream.deinit();
    
    // Send headers
    const headers = [_]http2.Header{
        .{ .name = ":method", .value = "POST" },
        .{ .name = ":path", .value = "/test.Service/BidirectionalStream" },
    };
    try stream.sendHeaders(&headers);
    
    // Send multiple messages
    try stream.sendData("Message 1", false);
    try stream.sendData("Message 2", false);
    try stream.sendData("Message 3", true); // End stream
    
    try std.testing.expect(stream.state == .half_closed_local);
    try std.testing.expect(mock_conn.sent_frames.items.len == 4); // 1 headers + 3 data frames
    
    // Verify frames
    try std.testing.expect(mock_conn.sent_frames.items[0].frame_type == .headers);
    try std.testing.expect(mock_conn.sent_frames.items[1].frame_type == .data);
    try std.testing.expect(mock_conn.sent_frames.items[2].frame_type == .data);
    try std.testing.expect(mock_conn.sent_frames.items[3].frame_type == .data);
    
    // Last frame should have END_STREAM flag
    const last_frame = mock_conn.sent_frames.items[3];
    try std.testing.expect(last_frame.flags & http2.Http2Frame.FLAG_END_STREAM != 0);
}

test "grpc stream flow control window update" {
    const allocator = std.testing.allocator;
    
    var mock_conn = MockHttp2Connection.init(allocator);
    defer mock_conn.deinit();
    
    var stream = try streaming.GrpcStream.init(
        allocator,
        1,
        .server_streaming,
        @ptrCast(&mock_conn),
    );
    defer stream.deinit();
    
    stream.state = .open;
    stream.headers_received = true;
    
    // Simulate receiving large data that triggers window update
    stream.local_window = 30000; // Reduce window to trigger update
    
    const large_data = try allocator.alloc(u8, 5000);
    defer allocator.free(large_data);
    @memset(large_data, 0xAA);
    
    const data_frame = try http2.Http2Frame.createData(allocator, 1, large_data, false);
    defer data_frame.deinit(allocator);
    
    try mock_conn.injectFrame(data_frame);
    
    const received = try stream.receiveMessage();
    defer if (received) |msg| allocator.free(msg);
    
    // Should have sent a window update
    var window_update_sent = false;
    for (mock_conn.sent_frames.items) |frame| {
        if (frame.frame_type == .window_update) {
            window_update_sent = true;
            break;
        }
    }
    try std.testing.expect(window_update_sent);
}

test "streaming grpc client multiple streams" {
    const allocator = std.testing.allocator;
    
    var mock_conn = MockHttp2Connection.init(allocator);
    defer mock_conn.deinit();
    
    var client = streaming.StreamingGrpcClient.init(allocator, @ptrCast(&mock_conn));
    defer client.deinit();
    
    // Create multiple streams
    const stream1 = try client.createStream(.unary);
    const stream2 = try client.createStream(.server_streaming);
    const stream3 = try client.createStream(.bidirectional_streaming);
    
    try std.testing.expect(stream1.stream_id == 1);
    try std.testing.expect(stream2.stream_id == 3);
    try std.testing.expect(stream3.stream_id == 5);
    
    try std.testing.expect(client.streams.count() == 3);
    
    // Verify stream retrieval
    try std.testing.expect(client.getStream(1) == stream1);
    try std.testing.expect(client.getStream(3) == stream2);
    try std.testing.expect(client.getStream(5) == stream3);
    try std.testing.expect(client.getStream(7) == null);
    
    // Remove a stream
    client.removeStream(3);
    try std.testing.expect(client.streams.count() == 2);
    try std.testing.expect(client.getStream(3) == null);
}

test "grpc stream error handling and reset" {
    const allocator = std.testing.allocator;
    
    var mock_conn = MockHttp2Connection.init(allocator);
    defer mock_conn.deinit();
    
    var stream = try streaming.GrpcStream.init(
        allocator,
        1,
        .unary,
        @ptrCast(&mock_conn),
    );
    defer stream.deinit();
    
    stream.state = .open;
    
    // Reset stream with error code
    try stream.reset(8); // CANCEL error code
    
    try std.testing.expect(stream.state == .closed);
    try std.testing.expect(stream.isClosed());
    try std.testing.expect(!stream.canSend());
    try std.testing.expect(!stream.canReceive());
    
    // Should have sent RST_STREAM frame
    try std.testing.expect(mock_conn.sent_frames.items.len == 1);
    const rst_frame = mock_conn.sent_frames.items[0];
    try std.testing.expect(rst_frame.frame_type == .rst_stream);
    try std.testing.expect(rst_frame.stream_id == 1);
    
    const error_code = std.mem.readInt(u32, rst_frame.payload[0..4], .big);
    try std.testing.expect(error_code == 8);
}

test "grpc stream trailers handling" {
    const allocator = std.testing.allocator;
    
    var mock_conn = MockHttp2Connection.init(allocator);
    defer mock_conn.deinit();
    
    var stream = try streaming.GrpcStream.init(
        allocator,
        1,
        .unary,
        @ptrCast(&mock_conn),
    );
    defer stream.deinit();
    
    stream.state = .open;
    
    // Send trailers (implies end of stream)
    const trailers = [_]http2.Header{
        .{ .name = "grpc-status", .value = "0" },
        .{ .name = "grpc-message", .value = "OK" },
    };
    
    try stream.sendTrailers(&trailers);
    
    try std.testing.expect(stream.state == .half_closed_local);
    try std.testing.expect(mock_conn.sent_frames.items.len == 1);
    
    const trailer_frame = mock_conn.sent_frames.items[0];
    try std.testing.expect(trailer_frame.frame_type == .headers);
    try std.testing.expect(trailer_frame.flags & http2.Http2Frame.FLAG_END_STREAM != 0);
    try std.testing.expect(trailer_frame.flags & http2.Http2Frame.FLAG_END_HEADERS != 0);
}

// Integration test simulating a complete gRPC streaming workflow
test "complete grpc streaming workflow" {
    const allocator = std.testing.allocator;
    
    var mock_conn = MockHttp2Connection.init(allocator);
    defer mock_conn.deinit();
    
    var client = streaming.StreamingGrpcClient.init(allocator, @ptrCast(&mock_conn));
    defer client.deinit();
    
    // Create bidirectional stream for PD ScanRegions
    const stream = try client.createStream(.bidirectional_streaming);
    
    // 1. Send initial headers
    const headers = [_]http2.Header{
        .{ .name = ":method", .value = "POST" },
        .{ .name = ":path", .value = "/pdpb.PD/ScanRegions" },
        .{ .name = ":scheme", .value = "https" },
        .{ .name = ":authority", .value = "pd.example.com:2379" },
        .{ .name = "content-type", .value = "application/grpc+proto" },
        .{ .name = "grpc-encoding", .value = "gzip" },
    };
    try stream.sendHeaders(&headers);
    
    // 2. Send request message
    const request_data = "scan_regions_request_protobuf_data";
    try stream.sendData(request_data, false);
    
    // 3. Simulate receiving response headers
    const response_headers = [_]http2.Header{
        .{ .name = ":status", .value = "200" },
        .{ .name = "content-type", .value = "application/grpc+proto" },
        .{ .name = "grpc-encoding", .value = "gzip" },
    };
    const resp_headers_frame = try http2.Http2Frame.createHeaders(allocator, 1, &response_headers, false);
    defer resp_headers_frame.deinit(allocator);
    try mock_conn.injectFrame(resp_headers_frame);
    
    // 4. Simulate receiving multiple response messages
    const response1 = "region_batch_1_protobuf_data";
    const response2 = "region_batch_2_protobuf_data";
    
    const data_frame1 = try http2.Http2Frame.createData(allocator, 1, response1, false);
    defer data_frame1.deinit(allocator);
    try mock_conn.injectFrame(data_frame1);
    
    const data_frame2 = try http2.Http2Frame.createData(allocator, 1, response2, false);
    defer data_frame2.deinit(allocator);
    try mock_conn.injectFrame(data_frame2);
    
    // 5. Simulate receiving trailers (end of stream)
    const trailers = [_]http2.Header{
        .{ .name = "grpc-status", .value = "0" },
        .{ .name = "grpc-message", .value = "OK" },
    };
    const trailers_frame = try http2.Http2Frame.createHeaders(allocator, 1, &trailers, true);
    defer trailers_frame.deinit(allocator);
    try mock_conn.injectFrame(trailers_frame);
    
    // 6. Receive messages
    const msg1 = try stream.receiveMessage();
    defer if (msg1) |m| allocator.free(m);
    try std.testing.expect(msg1 != null);
    try std.testing.expect(std.mem.eql(u8, msg1.?, response1));
    
    const msg2 = try stream.receiveMessage();
    defer if (msg2) |m| allocator.free(m);
    try std.testing.expect(msg2 != null);
    try std.testing.expect(std.mem.eql(u8, msg2.?, response2));
    
    const msg3 = try stream.receiveMessage(); // Should be null (end of stream)
    try std.testing.expect(msg3 == null);
    
    // 7. Verify final state
    try std.testing.expect(stream.state == .half_closed_remote);
    try std.testing.expect(stream.trailers_received);
    
    // 8. Close our side
    try stream.sendEndStream();
    try std.testing.expect(stream.state == .closed);
}
