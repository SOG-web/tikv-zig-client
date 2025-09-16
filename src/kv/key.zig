// TiKV client Zig - kv/key
const std = @import("std");
const HEX_LOWER: []const u8 = "0123456789abcdef";

/// NextKey returns the next key in byte-order by appending a 0x00 byte.
/// Caller owns the returned memory.
pub fn nextKey(alloc: std.mem.Allocator, k: []const u8) ![]u8 {
    var buf = try alloc.alloc(u8, k.len + 1);
    std.mem.copyForwards(u8, buf[0..k.len], k);
    buf[k.len] = 0;
    return buf;
}

/// PrefixNextKey returns the next prefix key.
/// Assume there are keys like:
///
///   rowkey1
///   rowkey1_column1
///   rowkey1_column2
///   rowKey2
///
/// If we seek 'rowkey1' NextKey, we will get 'rowkey1_column1'.
/// If we seek 'rowkey1' PrefixNextKey, we will get 'rowkey2'.
/// If increment overflows all bytes (e.g. 0xFF..FF), returns an empty slice.
pub fn prefixNextKey(alloc: std.mem.Allocator, k: []const u8) ![]u8 {
    var buf = try alloc.alloc(u8, k.len);
    std.mem.copyForwards(u8, buf, k);
    var i: usize = k.len;
    var overflow_all: bool = true;
    while (i > 0) {
        i -= 1;
        buf[i] +%= 1;
        if (buf[i] != 0) {
            overflow_all = false;
            break;
        }
    }
    if (overflow_all) {
        // Unlike TiDB, for the specific key 0xFF
        // we return empty slice instead of {0xFF, 0x0}
        alloc.free(buf);
        return alloc.alloc(u8, 0);
    }
    return buf;
}

/// CmpKey compares two keys: 0 if a==b, -1 if a<b, +1 if a>b.
pub fn cmpKey(a: []const u8, b: []const u8) i32 {
    const c = std.mem.order(u8, a, b);
    return switch (c) {
        .eq => 0,
        .lt => -1,
        .gt => 1,
    };
}

/// strKey returns hex string for key. Caller owns the returned memory.
pub fn strKey(alloc: std.mem.Allocator, k: []const u8) ![]u8 {
    var out = try alloc.alloc(u8, k.len * 2);
    var j: usize = 0;
    for (k) |b| {
        out[j] = HEX_LOWER[(b >> 4) & 0x0F];
        out[j + 1] = HEX_LOWER[b & 0x0F];
        j += 2;
    }
    return out;
}

/// KeyRange represents a range where StartKey <= key < EndKey.
pub const KeyRange = struct {
    start_key: []const u8,
    end_key: []const u8,
};

// -------------------- Tests --------------------

test "nextKey appends zero" {
    const a = "abc";
    const gpa = std.testing.allocator;
    const k = try nextKey(gpa, a);
    defer gpa.free(k);
    try std.testing.expectEqual(@as(usize, 4), k.len);
    const hex = try strKey(gpa, k);
    defer gpa.free(hex);
    try std.testing.expectEqualStrings("61626300", hex);
}

test "prefixNextKey basic" {
    const gpa = std.testing.allocator;
    const k = try prefixNextKey(gpa, &[_]u8{ 0x61, 0xff });
    defer gpa.free(k);
    try std.testing.expectEqual(@as(usize, 2), k.len);
    try std.testing.expect(k[0] == 0x62);
}

test "prefixNextKey overflow all FF returns empty" {
    const gpa = std.testing.allocator;
    const k1 = try prefixNextKey(gpa, &[_]u8{0xff});
    defer gpa.free(k1);
    try std.testing.expectEqual(@as(usize, 0), k1.len);

    const k2 = try prefixNextKey(gpa, &[_]u8{ 0xff, 0xff });
    defer gpa.free(k2);
    try std.testing.expectEqual(@as(usize, 0), k2.len);

    const k3 = try prefixNextKey(gpa, &[_]u8{ 0xff, 0xff, 0xff, 0xff });
    defer gpa.free(k3);
    try std.testing.expectEqual(@as(usize, 0), k3.len);
}
