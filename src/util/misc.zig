const std = @import("std");

pub const GCTimeFormat = "20060102-15:04:05 -0700"; // Go layout string (documentary only)
pub const ParsedGCTime = struct {
    year: i32,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    // offset from UTC in minutes, e.g. +0200 => 120, -0700 => -420
    tz_offset_minutes: i16,
};

// FormatBytes produces a human-readable string, matching Go's util.FormatBytes logic.
// Examples: "100 Bytes", "1.5 KB", "10 MB", "3.25 GB".
pub fn formatBytesAlloc(allocator: std.mem.Allocator, num_bytes: i64) ![]u8 {
    if (num_bytes <= byteSizeKB) {
        return try bytesToStringAlloc(allocator, num_bytes);
    }
    const unit, const unit_str = getByteUnit(num_bytes);
    if (unit == byteSizeBB) {
        return try bytesToStringAlloc(allocator, num_bytes);
    }
    const v = @as(f64, @floatFromInt(num_bytes)) / @as(f64, @floatFromInt(unit));
    var decimal: u8 = 1;
    if (@mod(num_bytes, unit) == 0) {
        decimal = 0;
    } else if (v < 10.0) {
        decimal = 2;
    }
    return try std.fmt.allocPrint(allocator, "{d:.{}} {s}", .{ v, decimal, unit_str });
}

pub const byteSizeGB: i64 = 1 << 30;
pub const byteSizeMB: i64 = 1 << 20;
pub const byteSizeKB: i64 = 1 << 10;
pub const byteSizeBB: i64 = 1;

fn getByteUnit(b: i64) struct { i64, []const u8 } {
    if (b > byteSizeGB) return .{ byteSizeGB, "GB" };
    if (b > byteSizeMB) return .{ byteSizeMB, "MB" };
    if (b > byteSizeKB) return .{ byteSizeKB, "KB" };
    return .{ byteSizeBB, "Bytes" };
}

// BytesToString converts the memory consumption to a readable string.
pub fn bytesToStringAlloc(allocator: std.mem.Allocator, num_bytes: i64) ![]u8 {
    const GB = @as(f64, @floatFromInt(num_bytes)) / @as(f64, @floatFromInt(byteSizeGB));
    if (GB > 1.0) return try std.fmt.allocPrint(allocator, "{d} GB", .{GB});
    const MB = @as(f64, @floatFromInt(num_bytes)) / @as(f64, @floatFromInt(byteSizeMB));
    if (MB > 1.0) return try std.fmt.allocPrint(allocator, "{d} MB", .{MB});
    const KB = @as(f64, @floatFromInt(num_bytes)) / @as(f64, @floatFromInt(byteSizeKB));
    if (KB > 1.0) return try std.fmt.allocPrint(allocator, "{d} KB", .{KB});
    return try std.fmt.allocPrint(allocator, "{d} Bytes", .{num_bytes});
}

// ---- Duration formatting ----

const NS_PER_US: i64 = 1_000;
const NS_PER_MS: i64 = 1_000_000;
const NS_PER_S: i64 = 1_000_000_000;

fn getDurationUnit(ns: i64) struct { unit_ns: i64, suffix: []const u8 } {
    if (ns >= NS_PER_S) return .{ .unit_ns = NS_PER_S, .suffix = "s" };
    if (ns >= NS_PER_MS) return .{ .unit_ns = NS_PER_MS, .suffix = "ms" };
    if (ns >= NS_PER_US) return .{ .unit_ns = NS_PER_US, .suffix = "µs" };
    return .{ .unit_ns = 1, .suffix = "ns" };
}

// FormatDuration mirrors Go's FormatDuration pruning rules for readability:
// 1) if d <= 1µs, print original unit (ns) with no rounding.
// 2) choose unit among ns, µs, ms, s.
// 3) if value < 10, keep 2 decimals; else keep 1 decimal; if divisible, use 0 decimals.
pub fn formatDurationAlloc(allocator: std.mem.Allocator, ns: i64) ![]u8 {
    if (ns <= NS_PER_US) {
        return try std.fmt.allocPrint(allocator, "{d}ns", .{ns});
    }
    const u = getDurationUnit(ns);
    if (u.unit_ns == 1) {
        return try std.fmt.allocPrint(allocator, "{d}ns", .{ns});
    }
    const integer_ns = (ns / u.unit_ns) * u.unit_ns;
    var decimal = @as(f64, @floatFromInt(ns - integer_ns)) / @as(f64, @floatFromInt(u.unit_ns));
    if (ns < 10 * u.unit_ns) {
        decimal = std.math.round(decimal * 100.0) / 100.0;
    } else {
        decimal = std.math.round(decimal * 10.0) / 10.0;
    }
    const total = @as(f64, @floatFromInt(integer_ns)) / @as(f64, @floatFromInt(u.unit_ns)) + decimal;
    // choose decimals 0/1/2 depending on divisibility and magnitude
    var decimals: u8 = 1;
    if ((ns % u.unit_ns) == 0) decimals = 0 else if (ns < 10 * u.unit_ns) decimals = 2;
    return try std.fmt.allocPrint(allocator, "{d:.{}}{s}", .{ total, decimals, u.suffix });
}

// ToUpperASCIIInplace mutates ASCII letters to uppercase without allocation.
pub fn toUpperASCIIInplace(buf: []u8) void {
    var has_lower = false;
    for (buf) |c| {
        if (c >= 'a' and c <= 'z') { has_lower = true; break; }
    }
    if (!has_lower) return;
    for (buf) |*pc| {
        if (pc.* >= 'a' and pc.* <= 'z') pc.* -%= ('a' - 'A');
    }
}

// Encode to uppercase-hex bytes (no 0x prefix), returns owned []u8.
pub fn encodeToHexUpperAlloc(allocator: std.mem.Allocator, src: []const u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexUpper(src)});
}

// HexRegionKey returns uppercase-hex bytes for logs.
pub fn hexRegionKeyAlloc(allocator: std.mem.Allocator, key: []const u8) ![]u8 {
    const hex = try encodeToHexUpperAlloc(allocator, key);
    return hex; // already uppercase
}

// HexRegionKeyStr returns uppercase-hex as a string slice (same as bytes in Zig).
pub fn hexRegionKeyStrAlloc(allocator: std.mem.Allocator, key: []const u8) ![]u8 {
    return try hexRegionKeyAlloc(allocator, key);
}

// CompatibleParseGCTime parses time strings saved by gc_worker.
// Accepts either "YYYYMMDD-HH:MM:SS -0700" or the prefix without the trailing offset.
// Returns a ParsedGCTime with components and the parsed timezone offset in minutes (0 when absent).
pub fn compatibleParseGCTime(value: []const u8) error{InvalidFormat}!ParsedGCTime {
    // Split into date-time and optional offset
    var dt_slice = value;
    var tz_minutes: i16 = 0;
    if (std.mem.lastIndexOfScalar(u8, value, ' ')) |idx| {
        const maybe_tz = value[idx+1..];
        // Expect ±HHMM (5 bytes) if present; otherwise treat as no tz field
        if (maybe_tz.len == 5 and (maybe_tz[0] == '+' or maybe_tz[0] == '-')) {
            dt_slice = value[0..idx];
            const sign: i16 = if (maybe_tz[0] == '+') 1 else -1;
            const hh = std.fmt.parseInt(i16, maybe_tz[1..3], 10) catch return error.InvalidFormat;
            const mm = std.fmt.parseInt(i16, maybe_tz[3..5], 10) catch return error.InvalidFormat;
            tz_minutes = sign * (hh * 60 + mm);
        }
    }
    // Expect YYYYMMDD-HH:MM:SS => 8 + 1 + 8 = 17 chars
    if (dt_slice.len != 17 or dt_slice[8] != '-' or dt_slice[11] != ':' or dt_slice[14] != ':')
        return error.InvalidFormat;
    const y = std.fmt.parseInt(i32, dt_slice[0..4], 10) catch return error.InvalidFormat;
    const mo = std.fmt.parseInt(u8, dt_slice[4..6], 10) catch return error.InvalidFormat;
    const d = std.fmt.parseInt(u8, dt_slice[6..8], 10) catch return error.InvalidFormat;
    const hh = std.fmt.parseInt(u8, dt_slice[9..11], 10) catch return error.InvalidFormat;
    const mi = std.fmt.parseInt(u8, dt_slice[12..14], 10) catch return error.InvalidFormat;
    const ss = std.fmt.parseInt(u8, dt_slice[15..17], 10) catch return error.InvalidFormat;
    return .{ .year = y, .month = mo, .day = d, .hour = hh, .minute = mi, .second = ss, .tz_offset_minutes = tz_minutes };
}
