// TiKV client Zig - kv module root
const std = @import("std");

pub const key = @import("key.zig");
pub const keyflags = @import("keyflags.zig");
pub const types = @import("types.zig");

pub const ReturnedValue = types.ReturnedValue;
pub const LockCtx = types.LockCtx;
pub const ReplicaReadType = types.ReplicaReadType;
pub const Variables = types.Variables;

test "kv module loads" {
    _ = key;
    _ = keyflags;
    _ = types;
}
