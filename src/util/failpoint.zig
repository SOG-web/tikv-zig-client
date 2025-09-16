const std = @import("std");

// Minimal failpoint facility to mirror Go's util/failpoint.go semantics.
// For now, it only supports enabling/disabling evaluation.
// Can be extended to support named payloads if needed.

var enabled: bool = false;

pub const FailpointError = error{ Disabled };

pub fn enableFailpoints() void {
    enabled = true;
}

// evalFailpoint returns error.Disabled when failpoints are not enabled.
// When enabled, it simply returns success. Extend this API as needed to carry payloads.
pub fn evalFailpoint(name: []const u8) FailpointError!void {
    _ = name;
    if (!enabled) return FailpointError.Disabled;
}
