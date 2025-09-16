// TikvRPC CallRPC stub for RawKV subset (Option A)
// This is a placeholder that will invoke gRPC in a future step.
const std = @import("std");
const request = @import("request.zig");
const c = @import("../c.zig").c;

pub const Error = error{
    Unimplemented,
};

/// callRPC would normally route to a gRPC TikvClient, but for now returns Unimplemented.
/// Parameters mirror the Go signature conceptually: context, client, req.
pub fn callRPC(
    target: []const u8,
    req: *const request.Request,
) Error!request.Response {
    _ = target;
    _ = req;
    return Error.Unimplemented;
}

// test {
//     const arena = c.upb_Arena_New();
//     defer c.upb_Arena_Free(arena);
//     var r = try request.Request.newRawGet(arena, "k", "default");
//     try std.testing.expectError(Error.Unimplemented, callRPC("127.0.0.1:20160", &r));
// }
