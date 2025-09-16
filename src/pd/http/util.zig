const std = @import("std");
const types = @import("../types.zig");

pub const http = std.http;
pub const Uri = std.Uri;

pub const Error = types.Error;

pub fn isUnreserved(b: u8) bool {
    return (b >= 'A' and b <= 'Z') or (b >= 'a' and b <= 'z') or (b >= '0' and b <= '9') or b == '-' or b == '_' or b == '.' or b == '~';
}

/// Calculate exponential backoff with a small jitter (in milliseconds)
pub fn jitteredBackoffMs(attempt: usize) u64 {
    const capped: u6 = @intCast(if (attempt < 6) attempt else 6);
    var backoff_ms: u64 = 50 * (@as(u64, 1) << (capped - 1));
    const ticks = std.time.nanoTimestamp();
    backoff_ms += (@as(u64, @intCast(ticks)) & 31);
    return backoff_ms;
}

/// Perform an HTTP GET to `url`, writing the body into the provided Allocating writer.
/// Returns the written body slice on success. Logs errors and non-OK statuses centrally.
/// On errors: returns Error.OutOfMemory for OOM, Error.RpcError otherwise.
pub fn fetchGetInto(http_client: *std.http.Client, url: []const u8, aw: *std.Io.Writer.Allocating) Error![]const u8 {
    aw.clearRetainingCapacity();
    const response = http_client.fetch(.{
        .method = .GET,
        .location = .{ .url = url },
        .response_writer = &aw.writer,
    }) catch |err| {
        std.log.err("http fetch failed from {s}: {s}", .{ url, @errorName(err) });
        if (err == error.OutOfMemory) return Error.OutOfMemory;
        return Error.RpcError;
    };
    if (response.status != .ok) {
        std.debug.print("http status not ok from {s}: {s} ({d})\n", .{ url, @tagName(response.status), @intFromEnum(response.status) });
        return Error.RpcError;
    }
    return aw.written();
}

pub fn percentEncode(out: *std.ArrayList(u8), allocator: std.mem.Allocator, data: []const u8) !void {
    const hex = "0123456789ABCDEF";
    for (data) |c| {
        if (isUnreserved(c)) {
            try out.append(allocator, c);
        } else {
            try out.append(allocator, '%');
            try out.append(allocator, hex[c >> 4]);
            try out.append(allocator, hex[c & 0x0F]);
        }
    }
}

pub fn buildUrl(allocator: std.mem.Allocator, use_https: bool, endpoint: []const u8, path_prefix: []const u8, tail: []const u8) ![]u8 {
    // If endpoint lacks scheme, choose based on use_https flag
    const has_scheme = std.mem.startsWith(u8, endpoint, "http://") or std.mem.startsWith(u8, endpoint, "https://");
    const scheme = if (has_scheme) "" else if (use_https) "https://" else "http://";
    var list = std.ArrayList(u8){};
    errdefer list.deinit(allocator);
    try list.appendSlice(allocator, scheme);
    try list.appendSlice(allocator, endpoint);
    try list.appendSlice(allocator, path_prefix);
    try list.appendSlice(allocator, tail);
    return list.toOwnedSlice(allocator);
}
