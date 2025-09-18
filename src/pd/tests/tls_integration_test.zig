// Integration tests for TLS + ALPN + streaming gRPC functionality
const std = @import("std");
const pd = @import("../mod.zig");
const grpc_client = @import("../grpc_client.zig");
const tls = @import("../../grpc_client/tls.zig");
const http2 = @import("../../grpc_client/http2.zig");
const streaming = @import("../../grpc_client/streaming.zig");

const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;

// Test endpoints - use environment variable or default
const TEST_ENDPOINTS = [_][]const u8{
    "127.0.0.1:2379",
};

test "PD gRPC client with TLS configuration" {
    const allocator = testing.allocator;

    // Test TLS configuration creation
    const tls_config = grpc_client.TlsOptions{
        .server_name = "pd.example.com",
        .insecure_skip_verify = true, // For testing
        .alpn_protocols = &.{"h2"},
        .ca_pem = null,
        .client_cert_pem = null,
        .client_key_pem = null,
    };

    var client = try pd.PDClientFactory.grpc_with_transport_options(
        allocator, 
        &TEST_ENDPOINTS, 
        true,  // prefer_grpc
        true,  // use_https
        .{},
    );
    defer client.close();

    // Set TLS options
    grpc_client.setTlsOptions(client.ptr, tls_config);

    // Verify TLS configuration
    try expect(client.ptr.use_https);
    try expect(client.ptr.prefer_grpc);
    try expect(std.mem.eql(u8, client.ptr.tls.server_name.?, "pd.example.com"));
    try expect(client.ptr.tls.insecure_skip_verify);
}

test "HTTP/2 connection creation with ALPN" {
    const allocator = testing.allocator;

    // Test HTTP/2 connection configuration (without actual network connection)
    const tls_config = tls.TlsConfig{
        .server_name = "pd.tikv.io",
        .alpn_protocols = &.{"h2"},
        .insecure_skip_verify = false,
    };

    // Verify configuration structure
    try expect(std.mem.eql(u8, tls_config.server_name.?, "pd.tikv.io"));
    try expect(tls_config.alpn_protocols.len == 1);
    try expect(std.mem.eql(u8, tls_config.alpn_protocols[0], "h2"));
    try expect(!tls_config.insecure_skip_verify);
    
    // Use the config to verify it's not unused
    _ = tls_config;
}

test "gRPC streaming client creation" {
    const allocator = testing.allocator;

    var client = try pd.PDClientFactory.grpc_with_transport_options(
        allocator, 
        &TEST_ENDPOINTS, 
        true,  // prefer_grpc
        false, // use_https (for testing without TLS)
        .{},
    );
    defer client.close();

    // Test streaming client creation (mock - would require real connection)
    // This tests the API structure without network calls
    try expect(client.ptr.endpoints.len > 0);
    try expect(client.ptr.prefer_grpc);
}

test "HTTP/2 frame creation for gRPC" {
    const allocator = testing.allocator;

    // Test creating gRPC-specific HTTP/2 frames
    const grpc_headers = [_]http2.Header{
        .{ .name = ":method", .value = "POST" },
        .{ .name = ":path", .value = "/pdpb.PD/GetRegion" },
        .{ .name = ":scheme", .value = "https" },
        .{ .name = ":authority", .value = "pd.example.com:2379" },
        .{ .name = "content-type", .value = "application/grpc+proto" },
        .{ .name = "grpc-encoding", .value = "gzip" },
        .{ .name = "grpc-accept-encoding", .value = "gzip" },
        .{ .name = "user-agent", .value = "tikv-client-zig/1.0" },
        .{ .name = "grpc-timeout", .value = "30S" },
    };

    const headers_frame = try http2.Http2Frame.createHeaders(allocator, 1, &grpc_headers, false);
    defer headers_frame.deinit(allocator);

    try expect(headers_frame.frame_type == .headers);
    try expect(headers_frame.stream_id == 1);
    try expect(headers_frame.flags & http2.Http2Frame.FLAG_END_HEADERS != 0);

    // Test gRPC message frame (5-byte header + protobuf payload)
    const grpc_message = [_]u8{ 0, 0, 0, 0, 20 } ++ "mock_protobuf_payload"; // 5-byte header + 20 bytes
    const data_frame = try http2.Http2Frame.createData(allocator, 1, &grpc_message, true);
    defer data_frame.deinit(allocator);

    try expect(data_frame.frame_type == .data);
    try expect(data_frame.stream_id == 1);
    try expect(data_frame.flags & http2.Http2Frame.FLAG_END_STREAM != 0);
    try expect(data_frame.payload.len == grpc_message.len);
}

test "gRPC streaming workflow simulation" {
    const allocator = testing.allocator;

    // Mock HTTP/2 connection for testing
    var mock_connection = struct {
        allocator: std.mem.Allocator,
        sent_frames: std.ArrayList(http2.Http2Frame),

        pub fn init(alloc: std.mem.Allocator) @This() {
            return @This(){
                .allocator = alloc,
                .sent_frames = std.ArrayList(http2.Http2Frame).init(alloc),
            };
        }

        pub fn deinit(self: *@This()) void {
            for (self.sent_frames.items) |frame| {
                frame.deinit(self.allocator);
            }
            self.sent_frames.deinit();
        }

        pub fn sendFrame(self: *@This(), frame: http2.Http2Frame) !void {
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
            _ = self;
            return error.WouldBlock;
        }

        pub fn handleFrame(self: *@This(), frame: http2.Http2Frame) !void {
            frame.deinit(self.allocator);
        }
    }.init(allocator);
    defer mock_connection.deinit();

    // Create streaming client
    var streaming_client = streaming.StreamingGrpcClient.init(allocator, @ptrCast(&mock_connection));
    defer streaming_client.deinit();

    // Create bidirectional stream for PD ScanRegions
    const stream = try streaming_client.createStream(.bidirectional_streaming);

    // Send initial headers
    const headers = [_]http2.Header{
        .{ .name = ":method", .value = "POST" },
        .{ .name = ":path", .value = "/pdpb.PD/ScanRegions" },
        .{ .name = ":scheme", .value = "https" },
        .{ .name = ":authority", .value = "pd.example.com:2379" },
        .{ .name = "content-type", .value = "application/grpc+proto" },
        .{ .name = "grpc-encoding", .value = "gzip" },
    };
    try stream.sendHeaders(&headers);

    // Send request data
    const request_data = "scan_regions_request_data";
    try stream.sendData(request_data, false);

    // Send end of stream
    try stream.sendEndStream();

    // Verify frames were sent
    try expect(mock_connection.sent_frames.items.len == 3); // headers + data + end_stream
    try expect(mock_connection.sent_frames.items[0].frame_type == .headers);
    try expect(mock_connection.sent_frames.items[1].frame_type == .data);
    try expect(mock_connection.sent_frames.items[2].frame_type == .data); // end_stream frame

    // Verify stream state
    try expect(stream.state == .half_closed_local);
    try expect(stream.headers_sent);
}

test "TLS certificate configuration" {
    const allocator = testing.allocator;

    // Test client certificate configuration
    const client_cert = 
        \\-----BEGIN CERTIFICATE-----
        \\MIIBkTCB+wIJAL7Z8Z8Z8Z8ZMA0GCSqGSIb3DQEBCwUAMBQxEjAQBgNVBAMMCWxv
        \\Y2FsaG9zdDAeFw0yMzAxMDEwMDAwMDBaFw0yNDAxMDEwMDAwMDBaMBQxEjAQBgNV
        \\BAMMCWxvY2FsaG9zdDBcMA0GCSqGSIb3DQEBAQUAA0sAMEgCQQC8Z8Z8Z8Z8Z8Z8
        \\Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8
        \\Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8
        \\AgMBAAEwDQYJKoZIhvcNAQELBQADQQC8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8
        \\Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8Z8
        \\-----END CERTIFICATE-----
    ;

    const client_key = 
        \\-----BEGIN PRIVATE KEY-----
        \\MIIBVAIBADANBgkqhkiG9w0BAQEFAASCAT4wggE6AgEAAkEAvGfGfGfGfGfGfGfG
        \\fGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfG
        \\fGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfG
        \\wIDAQABAkEAvGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfG
        \\fGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfG
        \\fGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfGfG
        \\QIhALxnxnxnxnxnxnxnxnxnxnxnxnxnxnxnxnxnxnxnxnxnxnxnxnxnxnxnxnxn
        \\-----END PRIVATE KEY-----
    ;

    const tls_config = tls.TlsConfig{
        .server_name = "pd.example.com",
        .client_cert_pem = client_cert,
        .client_key_pem = client_key,
        .alpn_protocols = &.{"h2"},
        .insecure_skip_verify = true, // For testing
    };

    try expect(tls_config.client_cert_pem != null);
    try expect(tls_config.client_key_pem != null);
    try expect(std.mem.startsWith(u8, tls_config.client_cert_pem.?, "-----BEGIN CERTIFICATE-----"));
    try expect(std.mem.startsWith(u8, tls_config.client_key_pem.?, "-----BEGIN PRIVATE KEY-----"));
}

test "gRPC error handling with streaming" {
    const allocator = testing.allocator;

    // Mock connection that simulates errors
    var mock_connection = struct {
        allocator: std.mem.Allocator,
        should_error: bool = false,

        pub fn sendFrame(self: *@This(), frame: http2.Http2Frame) !void {
            _ = frame;
            if (self.should_error) {
                return error.ConnectionError;
            }
        }

        pub fn receiveFrame(self: *@This()) !http2.Http2Frame {
            _ = self;
            return error.ConnectionClosed;
        }

        pub fn handleFrame(self: *@This(), frame: http2.Http2Frame) !void {
            _ = self;
            frame.deinit(self.allocator);
        }
    }{ .allocator = allocator };

    var streaming_client = streaming.StreamingGrpcClient.init(allocator, @ptrCast(&mock_connection));
    defer streaming_client.deinit();

    const stream = try streaming_client.createStream(.unary);

    // Test error handling
    mock_connection.should_error = true;

    const headers = [_]http2.Header{
        .{ .name = ":method", .value = "POST" },
        .{ .name = ":path", .value = "/test.Service/Method" },
    };

    // Should handle connection error gracefully
    const result = stream.sendHeaders(&headers);
    try testing.expectError(error.ConnectionError, result);
}

test "production TLS configuration for PD" {
    const allocator = testing.allocator;

    // Test production-ready TLS configuration
    const production_tls = tls.TlsConfig{
        .server_name = "pd.tikv.io",
        .alpn_protocols = &.{"h2"},
        .insecure_skip_verify = false, // Verify certificates in production
        .ca_cert_pem = null, // Use system CA bundle
        .client_cert_pem = null, // No client cert for basic auth
        .client_key_pem = null,
    };

    // Verify production settings
    try expect(std.mem.eql(u8, production_tls.server_name.?, "pd.tikv.io"));
    try expect(!production_tls.insecure_skip_verify);
    try expect(production_tls.alpn_protocols.len == 1);
    try expect(std.mem.eql(u8, production_tls.alpn_protocols[0], "h2"));

    // Test development TLS configuration
    const dev_tls = tls.TlsConfig{
        .server_name = "localhost",
        .alpn_protocols = &.{"h2"},
        .insecure_skip_verify = true, // Skip verification for local development
    };

    try expect(dev_tls.insecure_skip_verify);
    try expect(std.mem.eql(u8, dev_tls.server_name.?, "localhost"));
}

// Performance test for streaming operations
test "streaming performance characteristics" {
    const allocator = testing.allocator;

    // Mock high-performance connection
    var mock_connection = struct {
        allocator: std.mem.Allocator,
        frame_count: u32 = 0,

        pub fn sendFrame(self: *@This(), frame: http2.Http2Frame) !void {
            _ = frame;
            self.frame_count += 1;
        }

        pub fn receiveFrame(self: *@This()) !http2.Http2Frame {
            _ = self;
            return error.WouldBlock;
        }

        pub fn handleFrame(self: *@This(), frame: http2.Http2Frame) !void {
            frame.deinit(self.allocator);
        }
    }{ .allocator = allocator };

    var streaming_client = streaming.StreamingGrpcClient.init(allocator, @ptrCast(&mock_connection));
    defer streaming_client.deinit();

    // Create multiple concurrent streams
    const num_streams = 10;
    var streams: [num_streams]*streaming.GrpcStream = undefined;

    for (0..num_streams) |i| {
        streams[i] = try streaming_client.createStream(.bidirectional_streaming);
        
        const headers = [_]http2.Header{
            .{ .name = ":method", .value = "POST" },
            .{ .name = ":path", .value = "/test.Service/Stream" },
        };
        try streams[i].sendHeaders(&headers);
    }

    // Verify all streams were created and headers sent
    try expect(streaming_client.streams.count() == num_streams);
    try expect(mock_connection.frame_count == num_streams); // One header frame per stream

    // Send data on all streams
    for (streams) |stream| {
        try stream.sendData("test_data", false);
    }

    try expect(mock_connection.frame_count == num_streams * 2); // Headers + data frames
}
