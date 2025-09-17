// PD module - Placement Driver client definitions
const std = @import("std");

pub const client = @import("client.zig");
pub const types = @import("types.zig");

// Re-exports
pub const PDClient = client.PDClient;
pub const PDClientFactory = client.PDClientFactory;
pub const Region = types.Region;
pub const KeyRange = types.KeyRange;
pub const Store = types.Store;

test {
    std.testing.refAllDecls(@This());
    // _ = @import("tests/http_smoke_test.zig");
    _ = @import("tests/grpc_smoke_test.zig");
}
