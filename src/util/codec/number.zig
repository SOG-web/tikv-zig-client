const std = @import("std");

// Number encoding utilities compatible with Go client util/codec/number.go
// - Fixed-width 64-bit integers in mem-comparable big-endian
// - Varint / Uvarint (LEB128, Go-compatible ZigZag for signed)
// - Mem-comparable varints (tagged big-endian) matching TiDB/TiKV

pub const sign_mask: u64 = 0x8000_0000_0000_0000;

pub const DecodeError = error{
    InsufficientBytes,
    Invalid,
    ValueTooLarge,
};

pub const DecodeUintResult = struct { rest: []const u8, value: u64 };
pub const DecodeIntResult = struct { rest: []const u8, value: i64 };
pub const DecodeUvarintResult = struct { rest: []const u8, value: u64 };
pub const DecodeVarintResult = struct { rest: []const u8, value: i64 };

// ---------- Helpers ----------
inline fn bePutU64(v: u64, out: *[8]u8) void {
    out[0] = @intCast((v >> 56) & 0xFF);
    out[1] = @intCast((v >> 48) & 0xFF);
    out[2] = @intCast((v >> 40) & 0xFF);
    out[3] = @intCast((v >> 32) & 0xFF);
    out[4] = @intCast((v >> 24) & 0xFF);
    out[5] = @intCast((v >> 16) & 0xFF);
    out[6] = @intCast((v >> 8) & 0xFF);
    out[7] = @intCast(v & 0xFF);
}

inline fn beGetU64(b: []const u8) u64 {
    return (@as(u64, b[0]) << 56) |
        (@as(u64, b[1]) << 48) |
        (@as(u64, b[2]) << 40) |
        (@as(u64, b[3]) << 32) |
        (@as(u64, b[4]) << 24) |
        (@as(u64, b[5]) << 16) |
        (@as(u64, b[6]) << 8) |
        (@as(u64, b[7]));
}

// ---------- Comparable fixed-width ints ----------
pub fn encodeIntToCmpUint(v: i64) u64 {
    const uv: u64 = @bitCast(v);
    return uv ^ sign_mask;
}

pub fn decodeCmpUintToInt(u: u64) i64 {
    const iv: i64 = @bitCast(u ^ sign_mask);
    return iv;
}

pub fn encodeIntAppend(dst: *std.ArrayList(u8), allocator: std.mem.Allocator, v: i64) !void {
    var buf: [8]u8 = undefined;
    bePutU64(encodeIntToCmpUint(v), &buf);
    try dst.appendSlice(allocator, &buf);
}

pub fn encodeInt(allocator: std.mem.Allocator, v: i64) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try encodeIntAppend(&list, allocator, v);
    return list.toOwnedSlice(allocator);
}

pub fn encodeIntDescAppend(dst: *std.ArrayList(u8), allocator: std.mem.Allocator, v: i64) !void {
    var buf: [8]u8 = undefined;
    bePutU64(~encodeIntToCmpUint(v), &buf);
    try dst.appendSlice(allocator, &buf);
}

pub fn encodeIntDesc(allocator: std.mem.Allocator, v: i64) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try encodeIntDescAppend(&list, allocator, v);
    return list.toOwnedSlice(allocator);
}

pub fn decodeInt(input: []const u8) DecodeError!DecodeIntResult {
    if (input.len < 8) return DecodeError.InsufficientBytes;
    const u = beGetU64(input[0..8]);
    const v = decodeCmpUintToInt(u);
    return .{ .rest = input[8..], .value = v };
}

pub fn decodeIntDesc(input: []const u8) DecodeError!DecodeIntResult {
    if (input.len < 8) return DecodeError.InsufficientBytes;
    const u = beGetU64(input[0..8]);
    const v = decodeCmpUintToInt(~u);
    return .{ .rest = input[8..], .value = v };
}

pub fn encodeUintAppend(dst: *std.ArrayList(u8), allocator: std.mem.Allocator, v: u64) !void {
    var buf: [8]u8 = undefined;
    bePutU64(v, &buf);
    try dst.appendSlice(allocator, &buf);
}

pub fn encodeUint(allocator: std.mem.Allocator, v: u64) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try encodeUintAppend(&list, allocator, v);
    return list.toOwnedSlice(allocator);
}

pub fn encodeUintDescAppend(dst: *std.ArrayList(u8), allocator: std.mem.Allocator, v: u64) !void {
    var buf: [8]u8 = undefined;
    bePutU64(~v, &buf);
    try dst.appendSlice(allocator, &buf);
}

pub fn encodeUintDesc(allocator: std.mem.Allocator, v: u64) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try encodeUintDescAppend(&list, allocator, v);
    return list.toOwnedSlice(allocator);
}

pub fn decodeUint(input: []const u8) DecodeError!DecodeUintResult {
    if (input.len < 8) return DecodeError.InsufficientBytes;
    const v = beGetU64(input[0..8]);
    return .{ .rest = input[8..], .value = v };
}

pub fn decodeUintDesc(input: []const u8) DecodeError!DecodeUintResult {
    if (input.len < 8) return DecodeError.InsufficientBytes;
    const v = beGetU64(input[0..8]);
    return .{ .rest = input[8..], .value = ~v };
}

// ---------- Standard Varints (Go-compatible) ----------

pub fn encodeUvarintAppend(dst: *std.ArrayList(u8), allocator: std.mem.Allocator, mut_v: u64) !void {
    var v = mut_v;
    while (v >= 0x80) {
        try dst.append(allocator, @as(u8, @intCast(v)) | 0x80);
        v >>= 7;
    }
    try dst.append(allocator, @as(u8, @intCast(v)));
}

pub fn encodeUvarint(allocator: std.mem.Allocator, v: u64) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try encodeUvarintAppend(&list, allocator, v);
    return list.toOwnedSlice(allocator);
}

// Go's Varint uses ZigZag transform on signed values
inline fn zigzagEncode(x: i64) u64 {
    const ux: u64 = @bitCast(x);
    const sign: u64 = @bitCast(x >> 63);
    return (ux << 1) ^ sign;
}

inline fn zigzagDecode(ux: u64) i64 {
    var x: i64 = @bitCast(ux >> 1);
    if ((ux & 1) != 0) x = ~x;
    return x;
}

pub fn encodeVarintAppend(dst: *std.ArrayList(u8), allocator: std.mem.Allocator, x: i64) !void {
    const ux = zigzagEncode(x);
    try encodeUvarintAppend(dst, allocator, ux);
}

pub fn encodeVarint(allocator: std.mem.Allocator, x: i64) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try encodeVarintAppend(&list, allocator, x);
    return list.toOwnedSlice(allocator);
}

pub fn decodeUvarint(input: []const u8) DecodeError!DecodeUvarintResult {
    var x: u64 = 0;
    var s: u6 = 0; // shift up to 63
    var i: usize = 0;
    while (i < input.len and i < 10) : (i += 1) {
        const b = input[i];
        if (b < 0x80) {
            if (i == 9 and b > 1) return DecodeError.ValueTooLarge; // overflow
            x |= (@as(u64, b) << s);
            return .{ .rest = input[i + 1 ..], .value = x };
        }
        x |= (@as(u64, b & 0x7F) << s);
        s += 7;
    }
    if (i >= input.len) return DecodeError.InsufficientBytes;
    return DecodeError.ValueTooLarge; // >10 bytes
}

pub fn decodeVarint(input: []const u8) DecodeError!DecodeVarintResult {
    const r = try decodeUvarint(input);
    return .{ .rest = r.rest, .value = zigzagDecode(r.value) };
}

// ---------- Mem-comparable Varints ----------
const negativeTagEnd: u8 = 8; // negative tag is (negativeTagEnd - length)
const positiveTagStart: u8 = 0xFF - 8; // positive tag is (positiveTagStart + length)

pub fn encodeComparableVarintAppend(dst: *std.ArrayList(u8), allocator: std.mem.Allocator, v: i64) !void {
    if (v < 0) {
        var length: u8 = undefined;
        if (v >= -0xFF) {
            length = 1;
        } else if (v >= -0xFFFF) {
            length = 2;
        } else if (v >= -0xFF_FFFF) {
            length = 3;
        } else if (v >= -0xFF_FF_FFFF) {
            length = 4;
        } else if (v >= -0xFF_FF_FF_FFFF) {
            length = 5;
        } else if (v >= -0xFF_FF_FF_FF_FFFF) {
            length = 6;
        } else if (v >= -0xFF_FF_FF_FF_FF_FFFF) {
            length = 7;
        } else {
            length = 8;
        }
        try dst.append(allocator, negativeTagEnd - length);
        var i: u8 = length;
        while (i > 0) : (i -= 1) {
            const shift: u6 = @intCast((i - 1) * 8);
            try dst.append(allocator, @intCast((v >> shift) & 0xFF));
        }
        return;
    }
    try encodeComparableUvarintAppend(dst, allocator, @intCast(v));
}

pub fn encodeComparableVarint(allocator: std.mem.Allocator, v: i64) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try encodeComparableVarintAppend(&list, allocator, v);
    return list.toOwnedSlice(allocator);
}

pub fn encodeComparableUvarintAppend(dst: *std.ArrayList(u8), allocator: std.mem.Allocator, v: u64) !void {
    if (v <= (positiveTagStart - negativeTagEnd)) {
        try dst.append(allocator, @intCast(v + negativeTagEnd));
        return;
    }
    var length: u8 = undefined;
    if (v <= 0xFF) {
        length = 1;
    } else if (v <= 0xFFFF) {
        length = 2;
    } else if (v <= 0xFF_FFFF) {
        length = 3;
    } else if (v <= 0xFF_FF_FFFF) {
        length = 4;
    } else if (v <= 0xFF_FF_FF_FFFF) {
        length = 5;
    } else if (v <= 0xFF_FF_FF_FF_FFFF) {
        length = 6;
    } else if (v <= 0xFF_FF_FF_FF_FF_FFFF) {
        length = 7;
    } else {
        length = 8;
    }
    try dst.append(allocator, positiveTagStart + length);
    var i: u8 = length;
    while (i > 0) : (i -= 1) {
        const shift: u6 = @intCast((i - 1) * 8);
        try dst.append(allocator, @intCast((v >> shift) & 0xFF));
    }
}

pub fn encodeComparableUvarint(allocator: std.mem.Allocator, v: u64) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try encodeComparableUvarintAppend(&list, allocator, v);
    return list.toOwnedSlice(allocator);
}

pub fn decodeComparableUvarint(input: []const u8) DecodeError!DecodeUvarintResult {
    if (input.len == 0) return DecodeError.InsufficientBytes;
    const first = input[0];
    var b = input[1..];
    if (first < negativeTagEnd) return DecodeError.Invalid;
    if (first <= positiveTagStart) {
        return .{ .rest = b, .value = @as(u64, first) - negativeTagEnd };
    }
    const length: usize = @intCast(@as(usize, first) - positiveTagStart);
    if (b.len < length) return DecodeError.InsufficientBytes;
    var v: u64 = 0;
    for (b[0..length]) |c| v = (v << 8) | c;
    return .{ .rest = b[length..], .value = v };
}

pub fn decodeComparableVarint(input: []const u8) DecodeError!DecodeVarintResult {
    if (input.len == 0) return DecodeError.InsufficientBytes;
    const first = input[0];
    var b = input[1..];
    if (first >= negativeTagEnd and first <= positiveTagStart) {
        return .{ .rest = b, .value = @as(i64, first) - negativeTagEnd };
    }

    var length: usize = undefined;
    var v: u64 = 0;
    var neg = false;
    if (first < negativeTagEnd) {
        neg = true;
        length = negativeTagEnd - first;
    } else {
        length = @intCast(@as(usize, first) - positiveTagStart);
    }
    if (b.len < length) return DecodeError.InsufficientBytes;
    if (neg) {
        // Mirror Go's algorithm: v starts as all ones and then consumes bytes.
        v = ~@as(u64, 0);
        for (b[0..length]) |c| v = (v << 8) | c;
        if (v <= @as(u64, std.math.maxInt(i64))) return DecodeError.Invalid;
        const signed: i64 = @bitCast(v);
        return .{ .rest = b[length..], .value = signed };
    } else {
        for (b[0..length]) |c| v = (v << 8) | c;
    }
    // positive
    if (first > positiveTagStart and v > @as(u64, std.math.maxInt(i64))) return DecodeError.Invalid;
    return .{ .rest = b[length..], .value = @intCast(v) };
}

// ---------- Tests ----------

test "fixed-width int/uint roundtrip" {
    const gpa = std.testing.allocator;
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);

    const ints = [_]i64{ 0, 1, -1, 123, -456, std.math.minInt(i64), std.math.maxInt(i64) };
    inline for (ints) |x| {
        buf.clearRetainingCapacity();
        try encodeIntAppend(&buf, gpa, x);
        const r1 = try decodeInt(buf.items);
        try std.testing.expectEqual(x, r1.value);

        buf.clearRetainingCapacity();
        try encodeIntDescAppend(&buf, gpa, x);
        const r2 = try decodeIntDesc(buf.items);
        try std.testing.expectEqual(x, r2.value);
    }

    const uints = [_]u64{ 0, 1, 123, 1 << 63, std.math.maxInt(u64) };
    inline for (uints) |u| {
        buf.clearRetainingCapacity();
        try encodeUintAppend(&buf, gpa, u);
        const r3 = try decodeUint(buf.items);
        try std.testing.expectEqual(u, r3.value);

        buf.clearRetainingCapacity();
        try encodeUintDescAppend(&buf, gpa, u);
        const r4 = try decodeUintDesc(buf.items);
        try std.testing.expectEqual(u, r4.value);
    }
}

test "varint/uvarint roundtrip" {
    const gpa = std.testing.allocator;
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);

    const signed = [_]i64{ 0, 1, -1, 63, -64, 64, -65, 127, -128, 128, -129, std.math.minInt(i64)/2, std.math.maxInt(i64)/2 };
    inline for (signed) |x| {
        buf.clearRetainingCapacity();
        try encodeVarintAppend(&buf, gpa, x);
        const rv = try decodeVarint(buf.items);
        try std.testing.expectEqual(x, rv.value);
    }

    const unsigned = [_]u64{ 0, 1, 127, 128, 255, 256, 16384, std.math.maxInt(u32), std.math.maxInt(u64) };
    inline for (unsigned) |u| {
        buf.clearRetainingCapacity();
        try encodeUvarintAppend(&buf, gpa, u);
        const ru = try decodeUvarint(buf.items);
        try std.testing.expectEqual(u, ru.value);
    }
}

test "comparable varint roundtrip" {
    const gpa = std.testing.allocator;
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);

    const vals_i = [_]i64{ -1, -255, -256, -257, -65_535, -65_536, 0, 1, 239, 240, 255, 256, 65_535, 65_536, std.math.maxInt(i32) };
    inline for (vals_i) |x| {
        buf.clearRetainingCapacity();
        try encodeComparableVarintAppend(&buf, gpa, x);
        const r = try decodeComparableVarint(buf.items);
        try std.testing.expectEqual(x, r.value);
    }

    const vals_u = [_]u64{ 0, 1, 239, 240, 255, 256, 65_535, 65_536, std.math.maxInt(u64) };
    inline for (vals_u) |u| {
        buf.clearRetainingCapacity();
        try encodeComparableUvarintAppend(&buf, gpa, u);
        const r = try decodeComparableUvarint(buf.items);
        try std.testing.expectEqual(u, r.value);
    }
}
