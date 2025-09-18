// Tests for HTTP/2 + TLS integration
const std = @import("std");
const http2_integration = @import("../http2_integration.zig");
const tls = @import("../tls.zig");

test "http2 tls integration headers" {
    const allocator = std.testing.allocator;

    // Test gRPC headers creation
    var headers = try http2_integration.Http2TlsConnection.createGrpcHeaders(
        allocator, 
        "/pdpb.PD/GetRegion", 
        "pd.example.com:2379"
    );
    defer headers.deinit();

    try std.testing.expect(headers.count() == 9);
    try std.testing.expect(std.mem.eql(u8, headers.get(":method").?, "POST"));
    try std.testing.expect(std.mem.eql(u8, headers.get("content-type").?, "application/grpc+proto"));
    try std.testing.expect(std.mem.eql(u8, headers.get(":path").?, "/pdpb.PD/GetRegion"));
}

test "tls config creation" {
    const config = tls.TlsConfig{
        .alpn_protocols = &.{ "h2", "http/1.1" },
        .server_name = "example.com",
    };
    
    try std.testing.expect(config.alpn_protocols.len == 2);
    try std.testing.expect(std.mem.eql(u8, config.alpn_protocols[0], "h2"));
}
