const std = @import("std");

// Minimal transport placeholders to let tikvrpc compile without a real RPC client.
// A real implementation can wrap gRPC C-core or another RPC stack.

pub const Transport = struct {
    // placeholder for future fields (e.g., channel, credentials)
};

pub const StreamHandle = opaque {}; // transport-defined stream state
