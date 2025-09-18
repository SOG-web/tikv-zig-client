// PD client common types
const std = @import("std");
const metapb = @import("kvproto").metapb;
const pdpb = @import("kvproto").pdpb;
const kvrpcpb = @import("kvproto").kvrpcpb;

pub const KeyRange = kvrpcpb.KeyRange;

pub const Store = metapb.Store;

pub const Region = metapb.Region;

/// Timestamp result returned by PD TSO
pub const TSOResult = pdpb.Timestamp;

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
