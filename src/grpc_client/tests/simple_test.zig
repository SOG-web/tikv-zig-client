// Simple tests for the cleaned up gRPC client
const std = @import("std");
const tls = @import("../tls.zig");
const http2_integration = @import("../http2_integration.zig");

test "tls config basic" {
    const config = tls.TlsConfig{
        .server_name = "example.com",
        .alpn_protocols = &.{"h2"},
    };
    
    try std.testing.expect(std.mem.eql(u8, config.server_name.?, "example.com"));
    try std.testing.expect(config.alpn_protocols.len == 1);
}

test "grpc headers creation" {
    const allocator = std.testing.allocator;
    
    var headers = try http2_integration.Http2TlsConnection.createGrpcHeaders(
        allocator,
        "/test.Service/Method",
        "localhost:8080"
    );
    defer headers.deinit();
    
    try std.testing.expect(headers.count() > 0);
    try std.testing.expect(std.mem.eql(u8, headers.get(":method").?, "POST"));
}
