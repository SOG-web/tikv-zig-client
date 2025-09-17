const std = @import("std");
const c = @cImport({
    @cInclude("zlib.h");
});

// TODO: Switch to zlib-ng (zlib-compat) for better performance when available.
// zlib-ng provides a drop-in zlib API and can be linked instead of system zlib.

pub const ZlibError = error{
    InitFailed,
    StreamError,
    DataError,
    MemError,
};

fn deflateGeneric(allocator: std.mem.Allocator, input: []const u8, level: c_int, window_bits: c_int) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);

    var strm: c.z_stream = std.mem.zeroes(c.z_stream);

    if (c.deflateInit2(&strm, level, c.Z_DEFLATED, window_bits, 8, c.Z_DEFAULT_STRATEGY) != c.Z_OK)
        return ZlibError.InitFailed;
    defer _ = c.deflateEnd(&strm);

    strm.next_in = @constCast(input.ptr);
    strm.avail_in = @intCast(input.len);

    const chunk = 16384;
    var out_buf: [chunk]u8 = undefined;

    while (true) {
        strm.next_out = @constCast(out_buf[0..].ptr);
        strm.avail_out = @intCast(out_buf.len);

        const ret = c.deflate(&strm, c.Z_FINISH);
        const have = out_buf.len - @as(usize, @intCast(strm.avail_out));
        if (have > 0) try out.appendSlice(allocator, out_buf[0..have]);

        if (ret == c.Z_STREAM_END) break;
        if (ret == c.Z_OK or ret == c.Z_BUF_ERROR) continue;
        return ZlibError.StreamError;
    }

    return out.toOwnedSlice(allocator);
}

fn inflateGeneric(allocator: std.mem.Allocator, input: []const u8, window_bits: c_int) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);

    var strm: c.z_stream = std.mem.zeroes(c.z_stream);

    if (c.inflateInit2(&strm, window_bits) != c.Z_OK)
        return ZlibError.InitFailed;
    defer _ = c.inflateEnd(&strm);

    strm.next_in = @constCast(input.ptr);
    strm.avail_in = @intCast(input.len);

    const chunk = 16384;
    var out_buf: [chunk]u8 = undefined;

    while (true) {
        strm.next_out = @constCast(out_buf[0..].ptr);
        strm.avail_out = @intCast(out_buf.len);

        const ret = c.inflate(&strm, c.Z_NO_FLUSH);
        switch (ret) {
            c.Z_STREAM_END => {},
            c.Z_OK => {},
            c.Z_BUF_ERROR => {},
            c.Z_NEED_DICT, c.Z_DATA_ERROR => return ZlibError.DataError,
            c.Z_MEM_ERROR => return ZlibError.MemError,
            else => return ZlibError.StreamError,
        }

        const have = out_buf.len - @as(usize, @intCast(strm.avail_out));
        if (have > 0) try out.appendSlice(allocator, out_buf[0..have]);

        if (ret == c.Z_STREAM_END) break;
        if (strm.avail_in == 0 and have == 0 and ret == c.Z_BUF_ERROR) break;
    }

    return out.toOwnedSlice(allocator);
}

pub fn gzipCompress(allocator: std.mem.Allocator, input: []const u8, level: i32) ![]u8 {
    return try deflateGeneric(allocator, input, @intCast(level), 15 + 16);
}

pub fn zlibCompress(allocator: std.mem.Allocator, input: []const u8, level: i32) ![]u8 {
    return try deflateGeneric(allocator, input, @intCast(level), 15);
}

pub fn deflateRawCompress(allocator: std.mem.Allocator, input: []const u8, level: i32) ![]u8 {
    return try deflateGeneric(allocator, input, @intCast(level), -15);
}

pub fn gzipDecompress(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    return try inflateGeneric(allocator, input, 15 + 16);
}

pub fn zlibDecompress(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    return try inflateGeneric(allocator, input, 15);
}

pub fn deflateRawDecompress(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    return try inflateGeneric(allocator, input, -15);
}
