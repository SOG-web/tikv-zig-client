const std = @import("std");

// Public API for grpc_client. Re-export primary types and submodules
// so users can `@import("grpc_client/mod.zig")`.

pub const GrpcClient = @import("client.zig").GrpcClient;
pub const Transport = @import("transport.zig").Transport;
pub const GrpcStatusInfo = @import("transport.zig").GrpcStatusInfo;

// Feature modules: expose entire modules to avoid symbol drift.
pub const features = struct {
    pub const compression = @import("features/compression.zig");
    pub const auth = @import("features/auth.zig");
    pub const streaming = @import("features/streaming.zig");
    pub const health = @import("features/health.zig");

    test {
        _ = compression;
        _ = auth;
        _ = streaming;
        _ = health;
    }
};

// HTTP/2 internals: re-export submodules for advanced usage (optional).
pub const http2 = struct {
    pub const connection = @import("http2/connection.zig");
    pub const frame = @import("http2/frame.zig");
    pub const stream = @import("http2/stream.zig");
    pub const hpack = @import("http2/hpack.zig");
    pub const hpack_compliant = @import("http2/hpack_compliant.zig");
    pub const huffman = @import("http2/huffman.zig");

    test {
        _ = connection;
        _ = frame;
        _ = stream;
        _ = hpack;
        _ = hpack_compliant;
        _ = huffman;
    }
};

test {
    _ = GrpcClient;
    _ = Transport;
    _ = features;
    _ = http2;
    // _ = @import("tests/transport_test.zig"); TODO: fix
    // _ = @import("tests/pool_test.zig"); TODO: fix
}
