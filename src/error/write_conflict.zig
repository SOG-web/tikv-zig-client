const std = @import("std");
const common = @import("common.zig");
const kvrpcpb = common.kvrpcpb;
const logz = common.logz;

pub const ErrWriteConflict = struct {
    start_ts: u64,
    conflict_ts: u64,
    conflict_commit_ts: u64,
    key: []const u8,
    primary: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, conflict: kvrpcpb.WriteConflict) ErrWriteConflict {
        return .{
            .start_ts = conflict.start_ts,
            .conflict_ts = conflict.conflict_ts,
            .conflict_commit_ts = conflict.conflict_commit_ts,
            .key = conflict.key,
            .primary = conflict.primary,
            .allocator = allocator,
        };
    }

    pub fn format(self: ErrWriteConflict, writer: anytype) !void {
        const key_display = if (self.key.len > 0) self.key else "<empty>";
        const primary_display = if (self.primary.len > 0) self.primary else "<empty>";
        try writer.print(
            "write conflict {{ start_ts: {}, conflict_ts: {}, conflict_commit_ts: {}, key: {s}, primary: {s} }}",
            .{ self.start_ts, self.conflict_ts, self.conflict_commit_ts, key_display, primary_display },
        );
    }

    pub fn error_string(self: ErrWriteConflict, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    pub fn format_to_buffer(self: ErrWriteConflict, buf: []u8) ![]u8 {
        const key_display = if (self.key.len > 0) self.key else "<empty>";
        const primary_display = if (self.primary.len > 0) self.primary else "<empty>";
        return std.fmt.bufPrint(
            buf,
            "write conflict {{ start_ts: {}, conflict_ts: {}, conflict_commit_ts: {}, key: {s}, primary: {s} }}",
            .{ self.start_ts, self.conflict_ts, self.conflict_commit_ts, key_display, primary_display },
        );
    }

    pub fn log_error(self: ErrWriteConflict) void {
        logz
            .err()
            .ctx("WriteConflict")
            .int("start_ts", self.start_ts)
            .int("conflict_ts", self.conflict_ts)
            .int("conflict_commit_ts", self.conflict_commit_ts)
            .string("key", self.key)
            .string("primary", self.primary)
            .log("Write conflict detected");
    }
};

pub fn newErrWriteConflictWithArgs(
    allocator: std.mem.Allocator,
    start_ts: u64,
    conflict_ts: u64,
    conflict_commit_ts: u64,
    key: []const u8,
) !ErrWriteConflict {
    return ErrWriteConflict{
        .start_ts = start_ts,
        .conflict_ts = conflict_ts,
        .conflict_commit_ts = conflict_commit_ts,
        .key = key,
        .primary = "",
        .allocator = allocator,
    };
}

pub const ErrWriteConflictInLatch = struct {
    start_ts: u64,
    conflict_ts: u64,
    key: []const u8,

    pub fn init(start_ts: u64, conflict_ts: u64, key: []const u8) ErrWriteConflictInLatch {
        return .{ .start_ts = start_ts, .conflict_ts = conflict_ts, .key = key };
    }

    pub fn format(self: ErrWriteConflictInLatch, writer: anytype) !void {
        const key_display = if (self.key.len > 0) self.key else "<empty>";
        try writer.print(
            "write conflict in latch, startTS: {}, conflictTS: {}, key: {s}",
            .{ self.start_ts, self.conflict_ts, key_display },
        );
    }

    pub fn error_string(self: ErrWriteConflictInLatch, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    pub fn format_to_buffer(self: ErrWriteConflictInLatch, buf: []u8) ![]u8 {
        const key_display = if (self.key.len > 0) self.key else "<empty>";
        return std.fmt.bufPrint(
            buf,
            "write conflict in latch, startTS: {}, conflictTS: {}, key: {s}",
            .{ self.start_ts, self.conflict_ts, key_display },
        );
    }

    pub fn log_error(self: ErrWriteConflictInLatch) void {
        logz
            .err()
            .ctx("WriteConflictInLatch")
            .int("start_ts", self.start_ts)
            .int("conflict_ts", self.conflict_ts)
            .string("key", self.key)
            .log("Write conflict in latch detected");
    }
};

pub fn isErrWriteConflict(err: anyerror) bool {
    _ = err;
    return false;
}

// tests
test "write conflict error details" {
    const allocator = std.testing.allocator;

    const write_conflict = ErrWriteConflict{
        .start_ts = 12345,
        .conflict_ts = 67890,
        .conflict_commit_ts = 11111,
        .key = "conflicted_key",
        .primary = "primary_key",
        .allocator = allocator,
    };

    var buf: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(buf[0..]);
    try write_conflict.format(stream.writer());
    const formatted = stream.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, formatted, "write conflict") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "12345") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "67890") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "11111") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "conflicted_key") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "primary_key") != null);
}
