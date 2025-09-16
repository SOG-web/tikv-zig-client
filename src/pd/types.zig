// PD client common types
const std = @import("std");

pub const KeyRange = struct {
    start_key: []const u8,
    end_key: []const u8,
};

/// Minimal Store info used by the client
pub const Store = struct {
    id: u64,
    address: []const u8,
};

/// Minimal Region info used by the client
pub const Region = struct {
    id: u64,
    start_key: []const u8,
    end_key: []const u8,
};

/// Timestamp result returned by PD TSO
pub const TSOResult = struct {
    physical: i64,
    logical: i64,
};

pub const Error = error{
    Unimplemented,
    NotFound,
    InvalidArgument,
    RpcError,
    OutOfMemory,
};

test {
    std.testing.refAllDecls(@This());
}
