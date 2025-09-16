const std = @import("std");
const c = @cImport({
    @cInclude("kvrpcpb.upb.h");
    @cInclude("upb/mem/arena.h");
    @cInclude("upb/base/string_view.h");
});

fn sv(bytes: []const u8) c.upb_StringView {
    return c.upb_StringView{ .data = @as([*]const u8, @ptrCast(bytes.ptr)), .size = bytes.len };
}

test "kvrpcpb.GetRequest encode/decode roundtrip" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = c.upb_Arena_New();
    defer c.upb_Arena_Free(a);

    const msg = c.kvrpcpb_GetRequest_new(a);
    try std.testing.expect(msg != null);

    // Set key field
    const key = "hello-key";
    c.kvrpcpb_GetRequest_set_key(msg, sv(key));

    // Serialize
    var out_len: usize = 0;
    const out_ptr = c.kvrpcpb_GetRequest_serialize(msg, a, &out_len);
    try std.testing.expect(out_ptr != null);
    const out = out_ptr[0..out_len];

    // Parse back
    const parsed = c.kvrpcpb_GetRequest_parse(@as([*]const u8, @ptrCast(out.ptr)), out_len, a);
    try std.testing.expect(parsed != null);

    // Verify field
    const got = c.kvrpcpb_GetRequest_key(parsed);
    try std.testing.expectEqualStrings(key, got.data[0..got.size]);
}
