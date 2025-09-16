const std = @import("std");

// Mem-comparable encoding for byte slices, compatible with TiKV/TiDB codec.EncodeBytes.
// Encoding format:
//   [group1][marker1] ... [groupN][markerN]
//   - group: 8 bytes (pad with 0x00)
//   - marker: 0xFF - pad_count
// Examples:
//   [] -> [0,0,0,0,0,0,0,0,247]
//   [1,2,3] -> [1,2,3,0,0,0,0,0,250]
//   [1,2,3,0] -> [1,2,3,0,0,0,0,0,251]
//   [1..8] -> [1..8,255, 0..0,247]
// Reference:
//   https://github.com/facebook/mysql-5.6/wiki/MyRocks-record-format#memcomparable-format

pub const enc_group_size: usize = 8;
pub const enc_marker: u8 = 0xFF;
pub const enc_pad: u8 = 0x00;

pub const DecodeBytesResult = struct {
    rest: []const u8,
    decoded: []u8,
};

pub const DecodeBytesError = error{
    InsufficientBytes,
    InvalidMarker,
    InvalidPadding,
};

// encodeBytesAppend appends the mem-comparable encoding of `data` to `dst`.
// It pre-reserves capacity for performance.
pub fn encodeBytesAppend(dst: *std.ArrayList(u8), allocator: std.mem.Allocator, data: []const u8) !void {
    // Pre-reserve capacity similar to Go's growth heuristic: ((len/8)+1) * 9
    const d_len: usize = data.len;
    const reserve: usize = ((d_len / enc_group_size) + 1) * (enc_group_size + 1);
    try dst.ensureUnusedCapacity(allocator, reserve);

    var idx: usize = 0;
    while (idx <= d_len) : (idx += enc_group_size) {
        const remain = d_len -| idx; // saturating subtract; when idx > d_len loop ends due to usize semantics
        var pad_count: usize = 0;
        if (remain >= enc_group_size) {
            try dst.appendSlice(allocator, data[idx .. idx + enc_group_size]);
        } else {
            pad_count = enc_group_size - remain;
            if (remain > 0) try dst.appendSlice(allocator, data[idx..]);
            // append padding zeros
            if (pad_count > 0) {
                // small stack buffer for up to 8 zeros
                var pads: [enc_group_size]u8 = [_]u8{enc_pad} ** enc_group_size;
                try dst.appendSlice(allocator, pads[0..pad_count]);
            }
        }
        const marker: u8 = enc_marker - @as(u8, @intCast(pad_count));
        try dst.append(allocator, marker);
        if (pad_count != 0) break; // last group handled
    }
}

// encodeBytes allocates and returns a newly owned slice containing the encoding.
pub fn encodeBytes(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try encodeBytesAppend(&list, allocator, data);
    return list.toOwnedSlice(allocator);
}

// decodeBytes decodes an encoding produced by encodeBytes/encodeBytesAppend.
// If `buf` is provided as an ArrayList, it will be reused to avoid allocations.
// Returns the leftover bytes from input and the decoded owned slice.
pub fn decodeBytes(allocator: std.mem.Allocator, input: []const u8, buf: ?*std.ArrayList(u8)) (DecodeBytesError || error{OutOfMemory})!DecodeBytesResult {
    var dst_list_opt = buf;
    var owned_tmp: std.ArrayList(u8) = undefined;
    if (dst_list_opt == null) {
        owned_tmp = .empty;
        dst_list_opt = &owned_tmp;
    }
    var dst_list = dst_list_opt.?;
    defer if (buf == null) dst_list.deinit(allocator);

    dst_list.clearRetainingCapacity();

    var b = input;
    while (true) {
        if (b.len < enc_group_size + 1) return DecodeBytesError.InsufficientBytes;
        const group_bytes = b[0 .. enc_group_size + 1];
        const group = group_bytes[0..enc_group_size];
        const marker = group_bytes[enc_group_size];

        const pad_count_u8: u8 = enc_marker - marker;
        if (pad_count_u8 > enc_group_size) return DecodeBytesError.InvalidMarker;
        const pad_count: usize = @intCast(pad_count_u8);
        const real_size: usize = enc_group_size - pad_count;

        try dst_list.appendSlice(allocator, group[0..real_size]);
        b = b[enc_group_size + 1 ..];

        if (pad_count != 0) {
            // validate padding bytes are zeros
            if (group.len > real_size) {
                for (group[real_size..]) |v| {
                    if (v != enc_pad) return DecodeBytesError.InvalidPadding;
                }
            }
            break;
        }
    }

    const out = try dst_list.toOwnedSlice(allocator);
    if (buf != null) {
        // Caller-provided buffer expects we keep ownership inside it, so we need to copy into new slice.
        // However, toOwnedSlice already returns ownership and resets the list; reinitialize list to keep using it.
        dst_list.* = .empty;
    }
    return .{ .rest = b, .decoded = out };
}

// Tests to ensure behavior matches Go util/codec/bytes.go examples.
test "encodeBytes basic examples" {
    const gpa = std.testing.allocator;

    // [] -> [0,0,0,0,0,0,0,0,247]
    {
        const enc = try encodeBytes(gpa, &[_]u8{});
        defer gpa.free(enc);
        try std.testing.expectEqual(@as(usize, 9), enc.len);
        try std.testing.expect(std.mem.eql(u8, enc, &[_]u8{ 0,0,0,0,0,0,0,0,247 }));
    }

    // [1,2,3] -> [1,2,3,0,0,0,0,0,250]
    {
        const enc = try encodeBytes(gpa, &[_]u8{1,2,3});
        defer gpa.free(enc);
        try std.testing.expect(std.mem.eql(u8, enc, &[_]u8{ 1,2,3,0,0,0,0,0,250 }));
    }

    // [1,2,3,0] -> [1,2,3,0,0,0,0,0,251]
    {
        const enc = try encodeBytes(gpa, &[_]u8{1,2,3,0});
        defer gpa.free(enc);
        try std.testing.expect(std.mem.eql(u8, enc, &[_]u8{ 1,2,3,0,0,0,0,0,251 }));
    }

    // [1..8] -> [1..8,255, 0..0,247]
    {
        const enc = try encodeBytes(gpa, &[_]u8{1,2,3,4,5,6,7,8});
        defer gpa.free(enc);
        var expected: [18]u8 = .{1,2,3,4,5,6,7,8,255, 0,0,0,0,0,0,0,0,247};
        try std.testing.expect(std.mem.eql(u8, enc, expected[0..]));
    }
}

test "encode/decode roundtrip" {
    const gpa = std.testing.allocator;

    const cases = [_][]const u8{
        &[_]u8{},
        &[_]u8{0},
        &[_]u8{1,2,3},
        &[_]u8{1,2,3,0},
        &[_]u8{1,2,3,4,5,6,7,8},
        &[_]u8{1,2,3,4,5,6,7,8,9},
        "\x00\xFF\x00\xFF",
    };

    for (cases) |c| {
        const enc = try encodeBytes(gpa, c);
        defer gpa.free(enc);
        const res = try decodeBytes(gpa, enc, null);
        defer gpa.free(res.decoded);
        try std.testing.expectEqual(@as(usize, 0), res.rest.len);
        try std.testing.expect(std.mem.eql(u8, c, res.decoded));
    }
}
