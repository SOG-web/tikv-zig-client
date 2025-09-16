const std = @import("std");
const util = @import("../util/mod.zig");
const bytes = util.codec.bytes;
const number = util.codec.number;

// Example: compose a mem-comparable key from (table_id, user_key, ts)
// - table_id: ascending (u64 big-endian)
// - user_key: mem-comparable bytes
// - ts (timestamp): descending so that newer versions sort first
// Returns an owned slice; caller frees with allocator.free
pub fn composeKey(allocator: std.mem.Allocator, table_id: u64, user_key: []const u8, ts: i64) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    try number.encodeUintAppend(&buf, allocator, table_id);
    try bytes.encodeBytesAppend(&buf, allocator, user_key);
    try number.encodeIntDescAppend(&buf, allocator, ts);

    return buf.toOwnedSlice(allocator);
}

// Demonstration tests verifying lexicographic ordering corresponds to field ordering
// of (table_id asc, user_key asc, ts desc).
test "composeKey ordering" {
    const gpa = std.testing.allocator;

    const k1 = try composeKey(gpa, 1, "abc", 10);
    defer gpa.free(k1);
    const k2 = try composeKey(gpa, 1, "abc", 11);
    defer gpa.free(k2);
    const k3 = try composeKey(gpa, 1, "abd", 1);
    defer gpa.free(k3);
    const k4 = try composeKey(gpa, 2, "aaa", 0);
    defer gpa.free(k4);

    // Same table_id and user_key, ts desc: newer first => k2 < k1
    try std.testing.expect(std.mem.lessThan(u8, k2, k1));

    // Same table_id, user_key asc: "abc" < "abd" => k1 < k3
    try std.testing.expect(std.mem.lessThan(u8, k1, k3));

    // table_id asc: 1 < 2 => k3 < k4
    try std.testing.expect(std.mem.lessThan(u8, k3, k4));
}
