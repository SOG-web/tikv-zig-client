// Tests for TLS + ALPN functionality
const std = @import("std");
const tls = @import("../tls.zig");
const http2 = @import("../http2.zig");

test "tls config with alpn" {
    const config = tls.TlsConfig{
        .alpn_protocols = &.{ "h2", "http/1.1" },
        .server_name = "example.com",
        .insecure_skip_verify = false,
    };
    
    try std.testing.expect(config.alpn_protocols.len == 2);
    try std.testing.expect(std.mem.eql(u8, config.alpn_protocols[0], "h2"));
    try std.testing.expect(std.mem.eql(u8, config.alpn_protocols[1], "http/1.1"));
    try std.testing.expect(std.mem.eql(u8, config.server_name.?, "example.com"));
}

test "tls config with client certificates" {
    const client_cert = "-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----";
    const client_key = "-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----";
    
    const config = tls.TlsConfig{
        .client_cert_pem = client_cert,
        .client_key_pem = client_key,
        .insecure_skip_verify = true, // For testing
    };
    
    try std.testing.expect(config.client_cert_pem != null);
    try std.testing.expect(config.client_key_pem != null);
    try std.testing.expect(config.insecure_skip_verify);
}

test "http2 connection with tls config" {
    const allocator = std.testing.allocator;
    
    // Test configuration creation (actual connection would require real server)
    const tls_config = tls.TlsConfig{
        .server_name = "pd.example.com",
        .alpn_protocols = &.{"h2"},
        .insecure_skip_verify = true, // For testing
    };
    
    // Verify config is properly structured
    try std.testing.expect(std.mem.eql(u8, tls_config.server_name.?, "pd.example.com"));
    try std.testing.expect(tls_config.alpn_protocols.len == 1);
    try std.testing.expect(std.mem.eql(u8, tls_config.alpn_protocols[0], "h2"));
}

// Mock TLS connection for testing without actual network
const MockTlsConnection = struct {
    negotiated_protocol: []const u8,
    
    pub fn isHttp2(self: *const @This()) bool {
        return std.mem.eql(u8, self.negotiated_protocol, "h2");
    }
    
    pub fn writeAll(self: *const @This(), data: []const u8) !void {
        _ = self;
        _ = data;
        // Mock implementation
    }
    
    pub fn readAll(self: *const @This(), buffer: []u8) !void {
        _ = self;
        // Mock implementation - fill with dummy data
        @memset(buffer, 0);
    }
};

test "http2 connection preface" {
    const allocator = std.testing.allocator;
    
    // Test HTTP/2 preface generation
    const preface = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";
    try std.testing.expect(preface.len == 24);
    
    // Test settings frame creation
    const settings = [_]http2.Setting{
        .{ .id = .enable_push, .value = 0 },
        .{ .id = .max_concurrent_streams, .value = 100 },
        .{ .id = .initial_window_size, .value = 65535 },
    };
    
    const settings_frame = try http2.Http2Frame.createSettings(allocator, &settings, false);
    defer settings_frame.deinit(allocator);
    
    try std.testing.expect(settings_frame.frame_type == .settings);
    try std.testing.expect(settings_frame.stream_id == 0);
    try std.testing.expect(settings_frame.flags == 0);
}

test "http2 headers with grpc metadata" {
    const allocator = std.testing.allocator;
    
    // Test gRPC-specific headers
    const headers = [_]http2.Header{
        .{ .name = ":method", .value = "POST" },
        .{ .name = ":path", .value = "/pdpb.PD/GetRegion" },
        .{ .name = ":scheme", .value = "https" },
        .{ .name = ":authority", .value = "pd.example.com:2379" },
        .{ .name = "content-type", .value = "application/grpc+proto" },
        .{ .name = "grpc-encoding", .value = "gzip" },
        .{ .name = "grpc-accept-encoding", .value = "gzip" },
        .{ .name = "user-agent", .value = "tikv-client-zig/1.0" },
    };
    
    const frame = try http2.Http2Frame.createHeaders(allocator, 1, &headers, false);
    defer frame.deinit(allocator);
    
    try std.testing.expect(frame.frame_type == .headers);
    try std.testing.expect(frame.stream_id == 1);
    try std.testing.expect(frame.flags & http2.Http2Frame.FLAG_END_HEADERS != 0);
}

test "http2 data frame with grpc message" {
    const allocator = std.testing.allocator;
    
    // Mock gRPC message (5-byte header + protobuf payload)
    const grpc_message = [_]u8{ 0, 0, 0, 0, 10 } ++ "test_data!"; // 5-byte header + 10 bytes data
    
    const frame = try http2.Http2Frame.createData(allocator, 1, &grpc_message, true);
    defer frame.deinit(allocator);
    
    try std.testing.expect(frame.frame_type == .data);
    try std.testing.expect(frame.stream_id == 1);
    try std.testing.expect(frame.flags & http2.Http2Frame.FLAG_END_STREAM != 0);
    try std.testing.expect(frame.payload.len == grpc_message.len);
}

test "http2 window update flow control" {
    const allocator = std.testing.allocator;
    
    const increment: u32 = 32768;
    const frame = try http2.Http2Frame.createWindowUpdate(allocator, 1, increment);
    defer frame.deinit(allocator);
    
    try std.testing.expect(frame.frame_type == .window_update);
    try std.testing.expect(frame.stream_id == 1);
    try std.testing.expect(frame.payload.len == 4);
    
    const decoded_increment = std.mem.readInt(u32, frame.payload[0..4], .big);
    try std.testing.expect(decoded_increment == increment);
}

test "http2 frame encoding and size limits" {
    const allocator = std.testing.allocator;
    
    // Test maximum frame size
    const max_payload_size = 16384; // Default max frame size
    const large_data = try allocator.alloc(u8, max_payload_size);
    defer allocator.free(large_data);
    @memset(large_data, 0xAA);
    
    const frame = try http2.Http2Frame.createData(allocator, 1, large_data, false);
    defer frame.deinit(allocator);
    
    const encoded = try frame.encode(allocator);
    defer allocator.free(encoded);
    
    // Frame header (9 bytes) + payload
    try std.testing.expect(encoded.len == 9 + max_payload_size);
    
    // Verify frame header encoding
    const length = std.mem.readInt(u24, encoded[0..3], .big);
    try std.testing.expect(length == max_payload_size);
    try std.testing.expect(encoded[3] == @intFromEnum(http2.Http2FrameType.data));
}

// Integration test for TLS + HTTP/2 + gRPC workflow
test "grpc over tls http2 workflow simulation" {
    const allocator = std.testing.allocator;
    
    // 1. TLS configuration for production PD
    const tls_config = tls.TlsConfig{
        .server_name = "pd.tikv.io",
        .alpn_protocols = &.{"h2"},
        .insecure_skip_verify = false,
    };
    
    // 2. HTTP/2 settings for gRPC
    const http2_settings = http2.Http2Settings{
        .enable_push = false,
        .max_concurrent_streams = 100,
        .initial_window_size = 65535,
        .max_frame_size = 16384,
    };
    
    // 3. gRPC request headers
    const grpc_headers = [_]http2.Header{
        .{ .name = ":method", .value = "POST" },
        .{ .name = ":path", .value = "/pdpb.PD/GetRegion" },
        .{ .name = ":scheme", .value = "https" },
        .{ .name = ":authority", .value = "pd.tikv.io:2379" },
        .{ .name = "content-type", .value = "application/grpc+proto" },
        .{ .name = "grpc-encoding", .value = "gzip" },
        .{ .name = "te", .value = "trailers" },
    };
    
    // 4. Create frames
    const headers_frame = try http2.Http2Frame.createHeaders(allocator, 1, &grpc_headers, false);
    defer headers_frame.deinit(allocator);
    
    const grpc_payload = [_]u8{ 0, 0, 0, 0, 5 } ++ "hello"; // gRPC message
    const data_frame = try http2.Http2Frame.createData(allocator, 1, &grpc_payload, true);
    defer data_frame.deinit(allocator);
    
    // 5. Verify workflow components
    try std.testing.expect(std.mem.eql(u8, tls_config.alpn_protocols[0], "h2"));
    try std.testing.expect(http2_settings.enable_push == false);
    try std.testing.expect(headers_frame.stream_id == 1);
    try std.testing.expect(data_frame.flags & http2.Http2Frame.FLAG_END_STREAM != 0);
}
