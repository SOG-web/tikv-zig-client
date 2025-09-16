const std = @import("std");

// Compile-only sanity: ensure generated headers are visible to Zig's C importer
// and key symbols/types are defined. Do not call any functions here to avoid
// linking the C runtime in this test artifact.
const c = @cImport({
    @cInclude("kvrpcpb.upb.h");
    @cInclude("upb/mem/arena.h");
    @cInclude("upb/base/string_view.h");
});

test "kvproto headers are available" {
    // Type presence checks (compile-time only)
    const T1 = c.kvrpcpb_GetRequest;
    const T2 = c.upb_Arena;
    const T3 = c.upb_StringView;
    // Prevent unused warnings
    std.testing.expect(@sizeOf(T1) > 0) catch unreachable;
    std.testing.expect(@sizeOf(*T2) >= 0) catch unreachable;
    std.testing.expect(@sizeOf(T3) == @sizeOf(struct { data: *const u8, size: usize })) catch unreachable;
}
