// Centralized C imports for upb and kvproto headers
pub const c = @cImport({
    // Core upb
    @cInclude("upb/mem/arena.h");
    @cInclude("upb/base/string_view.h");
    @cInclude("upb/message/array.h");
    @cInclude("upb/message/map.h");
    // Provide inline definition for UPB_PRIVATE(_upb_MiniTable_StrongReference)
    // used by generated headers. This is a header-only inclusion; no changes
    // to generated sources.
    @cInclude("upb/mini_table/internal/message.h");

    // kvproto generated headers used by the client
    @cInclude("kvrpcpb.upb.h");
    @cInclude("metapb.upb.h");
    @cInclude("tikvpb.upb.h");
    @cInclude("coprocessor.upb.h");
    @cInclude("mpp.upb.h");
    @cInclude("debugpb.upb.h");
    @cInclude("errorpb.upb.h");
});

const std = @import("std");

pub fn main() !void {
    // Create an upb arena and a simple kvproto message (RawGetRequest)
    const arena = c.upb_Arena_New();
    defer c.upb_Arena_Free(arena);

    const req = c.kvrpcpb_RawGetRequest_new(arena);
    // Set required fields using generated setters
    c.kvrpcpb_RawGetRequest_set_key(req, c.upb_StringView_FromString("key"));
    c.kvrpcpb_RawGetRequest_set_cf(req, c.upb_StringView_FromString("default"));

    // Print a sanity line to prove linkage succeeded
    const key = c.kvrpcpb_RawGetRequest_key(req);
    std.debug.print("RawGetRequest created; key.len={d}, cf.len={d}\n", .{ key.size, c.kvrpcpb_RawGetRequest_cf(req).size });
}

test "main" {
    try main();
}
