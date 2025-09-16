const std = @import("std");

/// Minimal transport context passed to per-transport implementations
/// to avoid cyclic imports.
pub const TransportCtx = struct {
    allocator: std.mem.Allocator,
    endpoints: [][]const u8,
    use_https: bool,
};
