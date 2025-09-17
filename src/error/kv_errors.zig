const std = @import("std");
const common = @import("common.zig");
const kvrpcpb = common.kvrpcpb;
const logz = common.logz;

pub const ErrCommitTsTooLarge = struct {
    commit_ts: u64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, commit_ts: u64) ErrCommitTsTooLarge {
        return .{ .commit_ts = commit_ts, .allocator = allocator };
    }

    pub fn format(self: ErrCommitTsTooLarge, writer: anytype) !void {
        try writer.print("commit timestamp too large: {}", .{self.commit_ts});
    }

    pub fn error_string(self: ErrCommitTsTooLarge, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    pub fn format_to_buffer(self: ErrCommitTsTooLarge, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "commit timestamp too large: {}", .{self.commit_ts});
    }

    pub fn log_error(self: ErrCommitTsTooLarge) void {
        logz.err().ctx("CommitTsTooLarge").int("commit_ts", self.commit_ts).log("Commit timestamp too large");
    }
};

pub const ErrKeyExist = struct {
    key: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, already_exist: kvrpcpb.AlreadyExist) ErrKeyExist {
        return .{ .key = already_exist.key, .allocator = allocator };
    }

    pub fn format(self: ErrKeyExist, writer: anytype) !void {
        const key_str = if (self.key.len > 0) self.key else "";
        try writer.print("key already exists: {s}", .{key_str});
    }

    pub fn error_string(self: ErrKeyExist, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    pub fn format_to_buffer(self: ErrKeyExist, buf: []u8) ![]u8 {
        const key_str = if (self.key.len > 0) self.key else "";
        return std.fmt.bufPrint(buf, "key already exists: {s}", .{key_str});
    }

    pub fn log_error(self: ErrKeyExist) void {
        const key_str = if (self.key.len > 0) self.key else "";
        logz.err().ctx("KeyExist").string("key", key_str).log("Key already exists");
    }
};

pub const ErrRetryable = struct {
    retryable: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, retryable: []const u8) !ErrRetryable {
        const owned_msg = try allocator.dupe(u8, retryable);
        return .{ .retryable = owned_msg, .allocator = allocator };
    }

    pub fn deinit(self: *ErrRetryable) void {
        self.allocator.free(self.retryable);
    }

    pub fn format(self: ErrRetryable, writer: anytype) !void {
        try writer.print("{s}", .{self.retryable});
    }

    pub fn error_string(self: ErrRetryable, allocator: std.mem.Allocator) ![]u8 {
        return allocator.dupe(u8, self.retryable);
    }

    pub fn format_to_buffer(self: ErrRetryable, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "{s}", .{self.retryable});
    }

    pub fn log_error(self: ErrRetryable) void {
        logz.err().ctx("Retryable").string("message", self.retryable).log("Retryable error occurred");
    }
};

pub const ErrTxnTooLarge = struct {
    size: usize,

    pub fn init(size: usize) ErrTxnTooLarge { return .{ .size = size }; }

    pub fn format(self: ErrTxnTooLarge, writer: anytype) !void {
        try writer.print("txn too large, size: {}.", .{self.size});
    }

    pub fn error_string(self: ErrTxnTooLarge, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    pub fn format_to_buffer(self: ErrTxnTooLarge, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "txn too large, size: {}.", .{self.size});
    }

    pub fn log_error(self: ErrTxnTooLarge) void {
        logz.err().ctx("TxnTooLarge").int("size", self.size).log("Transaction too large");
    }
};

pub const ErrEntryTooLarge = struct {
    limit: u64,
    size: u64,

    pub fn init(limit: u64, size: u64) ErrEntryTooLarge { return .{ .limit = limit, .size = size }; }

    pub fn format(self: ErrEntryTooLarge, writer: anytype) !void {
        try writer.print("entry size too large, size: {}, limit: {}.", .{ self.size, self.limit });
    }

    pub fn error_string(self: ErrEntryTooLarge, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    pub fn format_to_buffer(self: ErrEntryTooLarge, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "entry size too large, size: {}, limit: {}.", .{ self.size, self.limit });
    }

    pub fn log_error(self: ErrEntryTooLarge) void {
        logz.err().ctx("EntryTooLarge").int("size", self.size).int("limit", self.limit).log("Entry size too large");
    }
};

pub const ErrPDServerTimeout = struct {
    msg: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, msg: []const u8) !ErrPDServerTimeout {
        const owned_msg = try allocator.dupe(u8, msg);
        return .{ .msg = owned_msg, .allocator = allocator };
    }

    pub fn deinit(self: *ErrPDServerTimeout) void {
        self.allocator.free(self.msg);
    }

    pub fn format(self: ErrPDServerTimeout, writer: anytype) !void {
        try writer.print("{s}", .{self.msg});
    }

    pub fn error_string(self: ErrPDServerTimeout, allocator: std.mem.Allocator) ![]u8 {
        return allocator.dupe(u8, self.msg);
    }

    pub fn format_to_buffer(self: ErrPDServerTimeout, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "{s}", .{self.msg});
    }

    pub fn log_error(self: ErrPDServerTimeout) void {
        logz.err().ctx("PDServerTimeout").string("message", self.msg).log("PD server timeout occurred");
    }
};

pub const ErrGCTooEarly = struct {
    txn_start_ts: i64,
    gc_safe_point: i64,

    pub fn init(txn_start_ts: i64, gc_safe_point: i64) ErrGCTooEarly {
        return .{ .txn_start_ts = txn_start_ts, .gc_safe_point = gc_safe_point };
    }

    pub fn format(self: ErrGCTooEarly, writer: anytype) !void {
        try writer.print(
            "GC life time is shorter than transaction duration, transaction starts at {}, GC safe point is {}",
            .{ self.txn_start_ts, self.gc_safe_point },
        );
    }

    pub fn error_string(self: ErrGCTooEarly, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    pub fn format_to_buffer(self: ErrGCTooEarly, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(
            buf,
            "GC life time is shorter than transaction duration, transaction starts at {}, GC safe point is {}",
            .{ self.txn_start_ts, self.gc_safe_point },
        );
    }

    pub fn log_error(self: ErrGCTooEarly) void {
        logz.err().ctx("GCTooEarly").int("txn_start_ts", self.txn_start_ts).int("gc_safe_point", self.gc_safe_point).log("GC too early error");
    }
};

pub const ErrTokenLimit = struct {
    store_id: u64,

    pub fn init(store_id: u64) ErrTokenLimit { return .{ .store_id = store_id }; }

    pub fn format(self: ErrTokenLimit, writer: anytype) !void {
        try writer.print("Store token is up to the limit, store id = {}", .{self.store_id});
    }

    pub fn error_string(self: ErrTokenLimit, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    pub fn format_to_buffer(self: ErrTokenLimit, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "Store token is up to the limit, store id = {}", .{self.store_id});
    }

    pub fn log_error(self: ErrTokenLimit) void {
        logz.err().ctx("TokenLimit").int("store_id", self.store_id).log("Store token limit reached");
    }
};

// tests
test "error creation and formatting" {
    const txn_err = ErrTxnTooLarge.init(1024);
    var buf: [512]u8 = undefined;

    var stream = std.io.fixedBufferStream(buf[0..]);
    try txn_err.format(stream.writer());
    const formatted_direct = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, formatted_direct, "txn too large") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted_direct, "1024") != null);

    const entry_err = ErrEntryTooLarge.init(512, 1024);
    stream.reset();
    try entry_err.format(stream.writer());
    const formatted2 = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, formatted2, "entry size too large") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted2, "size: 1024") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted2, "limit: 512") != null);
}

test "error formatting and checking" {
    const allocator = std.testing.allocator;

    var retryable_err = try ErrRetryable.init(allocator, "test retryable message");
    defer retryable_err.deinit();

    var buf: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(buf[0..]);
    try retryable_err.format(stream.writer());
    const formatted = stream.getWritten();
    try std.testing.expectEqualStrings("test retryable message", formatted);

    var pd_timeout = try ErrPDServerTimeout.init(allocator, "PD timeout occurred");
    defer pd_timeout.deinit();

    stream.reset();
    try pd_timeout.format(stream.writer());
    const pd_formatted = stream.getWritten();
    try std.testing.expectEqualStrings("PD timeout occurred", pd_formatted);
}
