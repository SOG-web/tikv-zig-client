const std = @import("std");
const common = @import("common.zig");
const kvrpcpb = common.kvrpcpb;
const logz = common.logz;

pub const ErrAssertionFailed = struct {
    assertion_failed: *kvrpcpb.AssertionFailed,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, assertion_failed: *kvrpcpb.AssertionFailed) ErrAssertionFailed {
        return .{ .assertion_failed = assertion_failed, .allocator = allocator };
    }

    pub fn format(self: ErrAssertionFailed, writer: anytype) !void {
        const start_ts = self.assertion_failed.start_ts;
        const key = self.assertion_failed.key;
        const assertion = self.assertion_failed.assertion;
        const key_str = if (key.len > 0) key[0..key.len] else "<empty>";
        try writer.print("assertion failed: start_ts={}, key={s}, assertion={}", .{ start_ts, key_str, assertion });
    }

    pub fn error_string(self: ErrAssertionFailed, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    pub fn format_to_buffer(self: ErrAssertionFailed, buf: []u8) ![]u8 {
        const start_ts = self.assertion_failed.start_ts;
        const key = self.assertion_failed.key;
        const assertion = self.assertion_failed.assertion;
        const key_str = if (key.len > 0) key[0..key.len] else "<empty>";
        return std.fmt.bufPrint(buf, "assertion failed: start_ts={}, key={s}, assertion={}", .{ start_ts, key_str, assertion });
    }

    pub fn log_error(self: ErrAssertionFailed) void {
        const start_ts = self.assertion_failed.start_ts;
        const key = self.assertion_failed.key;
        const assertion = self.assertion_failed.assertion;
        const key_str = if (key.len > 0) key[0..key.len] else "<empty>";
        logz.err().ctx("AssertionFailed").int("start_ts", start_ts).string("key", key_str).int("assertion", assertion).log("Assertion failed");
    }
};
