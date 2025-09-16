// Copyright 2021 TiKV Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

const std = @import("std");
const c = @cImport({
    @cInclude("kvrpcpb.upb.h");
    @cInclude("pdpb.upb.h");
});

// Mock logz for testing environment
const logz = if (@import("builtin").is_test) struct {
    pub fn err() MockLogger {
        return MockLogger{};
    }
    const MockLogger = struct {
        pub fn ctx(self: MockLogger, _: []const u8) MockLogger {
            return self;
        }
        pub fn int(self: MockLogger, _: []const u8, _: anytype) MockLogger {
            return self;
        }
        pub fn string(self: MockLogger, _: []const u8, _: []const u8) MockLogger {
            return self;
        }
        pub fn boolean(self: MockLogger, _: []const u8, _: bool) MockLogger {
            return self;
        }
        pub fn log(self: MockLogger, _: []const u8) void {
            _ = self;
        }
    };
} else @import("logz");

/// TiKV error enumeration
// Standard TiKV client errors
pub const TiKVError = error{
    // Response body is missing error
    BodyMissing,
    // TiDB is closing and send request to tikv fail, do not retry
    TiDBShuttingDown,
    // The related data not exist
    NotExist,
    // Cannot set nil value
    CannotSetNilValue,
    // Invalid transaction
    InvalidTxn,
    // TiKV server timeout
    TiKVServerTimeout,
    // TiFlash server timeout
    TiFlashServerTimeout,
    // Query interrupted
    QueryInterrupted,
    // TiKV stale command
    TiKVStaleCommand,
    // TiKV max timestamp not synced
    TiKVMaxTimestampNotSynced,
    // Lock acquire failed and no wait is set
    LockAcquireFailAndNoWaitSet,
    // Resolve lock timeout
    ResolveLockTimeout,
    // Lock wait timeout
    LockWaitTimeout,
    // TiKV server busy
    TiKVServerBusy,
    // TiFlash server busy
    TiFlashServerBusy,
    // Region unavailable
    RegionUnavailable,
    // Region data not ready when querying with safe_ts
    RegionDataNotReady,
    // Region not initialized
    RegionNotInitialized,
    // TiKV disk full
    TiKVDiskFull,
    // Unknown error
    Unknown,
    // Execution result undetermined
    ResultUndetermined,
};

// Mismatch cluster ID message
pub const MISMATCH_CLUSTER_ID = "mismatch cluster id";

/// Deadlock error wrapper
pub const ErrDeadlock = struct {
    deadlock: *c.kvrpcpb_Deadlock,
    is_retryable: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, deadlock: *c.kvrpcpb_Deadlock, is_retryable: bool) ErrDeadlock {
        return ErrDeadlock{
            .deadlock = deadlock,
            .is_retryable = is_retryable,
            .allocator = allocator,
        };
    }

    pub fn format(self: ErrDeadlock, writer: anytype) !void {
        // Extract deadlock information from protobuf
        const lock_ts = c.kvrpcpb_Deadlock_lock_ts(self.deadlock);
        const deadlock_key_hash = c.kvrpcpb_Deadlock_deadlock_key_hash(self.deadlock);
        const lock_key = c.kvrpcpb_Deadlock_lock_key(self.deadlock);

        // Get wait chain information
        var wait_chain_size: usize = 0;
        _ = c.kvrpcpb_Deadlock_wait_chain(self.deadlock, &wait_chain_size);

        const lock_key_str = if (lock_key.size > 0) lock_key.data[0..lock_key.size] else "<empty>";

        try writer.print("deadlock(lock_ts: {}, key_hash: {}, lock_key: {s}, wait_chain_len: {}, retryable: {})", .{ lock_ts, deadlock_key_hash, lock_key_str, wait_chain_size, self.is_retryable });
    }

    pub fn error_string(self: ErrDeadlock, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    /// More performant: format into provided buffer (no allocation)
    pub fn format_to_buffer(self: ErrDeadlock, buf: []u8) ![]u8 {
        const lock_ts = c.kvrpcpb_Deadlock_lock_ts(self.deadlock);
        const deadlock_key_hash = c.kvrpcpb_Deadlock_deadlock_key_hash(self.deadlock);
        const lock_key = c.kvrpcpb_Deadlock_lock_key(self.deadlock);
        var wait_chain_size: usize = 0;
        _ = c.kvrpcpb_Deadlock_wait_chain(self.deadlock, &wait_chain_size);
        const lock_key_str = if (lock_key.size > 0) lock_key.data[0..lock_key.size] else "<empty>";
        return std.fmt.bufPrint(buf, "deadlock(lock_ts: {}, key_hash: {}, lock_key: {s}, wait_chain_len: {}, retryable: {})", .{ lock_ts, deadlock_key_hash, lock_key_str, wait_chain_size, self.is_retryable });
    }

    /// Log error using logz (zero allocation, structured logging)
    pub fn log_error(self: ErrDeadlock) void {
        const lock_ts = c.kvrpcpb_Deadlock_lock_ts(self.deadlock);
        const deadlock_key_hash = c.kvrpcpb_Deadlock_deadlock_key_hash(self.deadlock);
        var wait_chain_size: usize = 0;
        _ = c.kvrpcpb_Deadlock_wait_chain(self.deadlock, &wait_chain_size);
        logz.err().ctx("Deadlock").int("lock_ts", lock_ts).int("key_hash", deadlock_key_hash).int("wait_chain_len", wait_chain_size).boolean("retryable", self.is_retryable).log("Deadlock detected");
    }
};

/// PD error wrapper
pub const PDError = struct {
    err: *c.pdpb_Error,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, err: *c.pdpb_Error) PDError {
        return PDError{
            .err = err,
            .allocator = allocator,
        };
    }

    pub fn format(self: PDError, writer: anytype) !void {
        // Extract PD error information from protobuf
        const error_type = c.pdpb_Error_type(self.err);
        const message = c.pdpb_Error_message(self.err);

        const msg_str = if (message.size > 0) message.data[0..message.size] else "";
        try writer.print("pd error(type: {}, message: {s})", .{ error_type, msg_str });
    }

    pub fn error_string(self: PDError, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    /// More performant: format into provided buffer (no allocation)
    pub fn format_to_buffer(self: PDError, buf: []u8) ![]u8 {
        const error_type = c.pdpb_Error_type(self.err);
        const message = c.pdpb_Error_message(self.err);
        const msg_str = if (message.size > 0) message.data[0..message.size] else "";
        return std.fmt.bufPrint(buf, "pd error(type: {}, message: {s})", .{ error_type, msg_str });
    }

    /// Log error using logz (zero allocation, structured logging)
    pub fn log_error(self: PDError) void {
        const error_type = c.pdpb_Error_type(self.err);
        const message = c.pdpb_Error_message(self.err);
        const msg_str = if (message.size > 0) message.data[0..message.size] else "";
        logz.err().ctx("PDError").int("type", error_type).string("message", msg_str).log("PD error occurred");
    }
};

/// Commit TS too large error wrapper
pub const ErrCommitTsTooLarge = struct {
    commit_ts_too_large: *c.kvrpcpb_CommitTsTooLarge,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, commit_ts_too_large: *c.kvrpcpb_CommitTsTooLarge) ErrCommitTsTooLarge {
        return ErrCommitTsTooLarge{
            .commit_ts_too_large = commit_ts_too_large,
            .allocator = allocator,
        };
    }

    pub fn format(self: ErrCommitTsTooLarge, writer: anytype) !void {
        // Extract commit timestamp from protobuf
        const commit_ts = c.kvrpcpb_CommitTsTooLarge_commit_ts(self.commit_ts_too_large);
        try writer.print("commit timestamp too large: {}", .{commit_ts});
    }

    pub fn error_string(self: ErrCommitTsTooLarge, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    /// More performant: format into provided buffer (no allocation)
    pub fn format_to_buffer(self: ErrCommitTsTooLarge, buf: []u8) ![]u8 {
        const commit_ts = c.kvrpcpb_CommitTsTooLarge_commit_ts(self.commit_ts_too_large);
        return std.fmt.bufPrint(buf, "commit timestamp too large: {}", .{commit_ts});
    }

    /// Log error using logz (zero allocation, structured logging)
    pub fn log_error(self: ErrCommitTsTooLarge) void {
        const commit_ts = c.kvrpcpb_CommitTsTooLarge_commit_ts(self.commit_ts_too_large);
        logz.err().ctx("CommitTsTooLarge").int("commit_ts", commit_ts).log("Commit timestamp too large");
    }
};

/// Key exist error wrapper
pub const ErrKeyExist = struct {
    already_exist: *c.kvrpcpb_AlreadyExist,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, already_exist: *c.kvrpcpb_AlreadyExist) ErrKeyExist {
        return ErrKeyExist{
            .already_exist = already_exist,
            .allocator = allocator,
        };
    }

    pub fn format(self: ErrKeyExist, writer: anytype) !void {
        // Extract key information from protobuf
        const key = c.kvrpcpb_AlreadyExist_key(self.already_exist);
        const key_str = if (key.size > 0) key.data[0..key.size] else "";

        try writer.print("key already exists: {s}", .{key_str});
    }

    pub fn error_string(self: ErrKeyExist, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    /// More performant: format into provided buffer (no allocation)
    pub fn format_to_buffer(self: ErrKeyExist, buf: []u8) ![]u8 {
        const key = c.kvrpcpb_AlreadyExist_key(self.already_exist);
        const key_str = if (key.size > 0) key.data[0..key.size] else "";
        return std.fmt.bufPrint(buf, "key already exists: {s}", .{key_str});
    }

    /// Log error using logz (zero allocation, structured logging)
    pub fn log_error(self: ErrKeyExist) void {
        const key = c.kvrpcpb_AlreadyExist_key(self.already_exist);
        const key_str = if (key.size > 0) key.data[0..key.size] else "";
        logz.err().ctx("KeyExist").string("key", key_str).log("Key already exists");
    }
};

/// Write conflict error wrapper
pub const ErrWriteConflict = struct {
    start_ts: u64,
    conflict_ts: u64,
    conflict_commit_ts: u64,
    key: []const u8,
    primary: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, conflict: *c.kvrpcpb_WriteConflict) ErrWriteConflict {
        const start_ts = c.kvrpcpb_WriteConflict_start_ts(conflict);
        const conflict_ts = c.kvrpcpb_WriteConflict_conflict_ts(conflict);
        const conflict_commit_ts = c.kvrpcpb_WriteConflict_conflict_commit_ts(conflict);
        const key_data = c.kvrpcpb_WriteConflict_key(conflict);
        const primary_data = c.kvrpcpb_WriteConflict_primary(conflict);

        const key = if (key_data.size > 0) key_data.data[0..key_data.size] else "";
        const primary = if (primary_data.size > 0) primary_data.data[0..primary_data.size] else "";

        return ErrWriteConflict{
            .start_ts = start_ts,
            .conflict_ts = conflict_ts,
            .conflict_commit_ts = conflict_commit_ts,
            .key = key,
            .primary = primary,
            .allocator = allocator,
        };
    }

    pub fn format(self: ErrWriteConflict, writer: anytype) !void {
        const key_display = if (self.key.len > 0) self.key else "<empty>";
        const primary_display = if (self.primary.len > 0) self.primary else "<empty>";

        try writer.print("write conflict {{ start_ts: {}, conflict_ts: {}, conflict_commit_ts: {}, key: {s}, primary: {s} }}", .{ self.start_ts, self.conflict_ts, self.conflict_commit_ts, key_display, primary_display });
    }

    pub fn error_string(self: ErrWriteConflict, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    /// More performant: format into provided buffer (no allocation)
    pub fn format_to_buffer(self: ErrWriteConflict, buf: []u8) ![]u8 {
        const key_display = if (self.key.len > 0) self.key else "<empty>";
        const primary_display = if (self.primary.len > 0) self.primary else "<empty>";
        return std.fmt.bufPrint(buf, "write conflict {{ start_ts: {}, conflict_ts: {}, conflict_commit_ts: {}, key: {s}, primary: {s} }}", .{ self.start_ts, self.conflict_ts, self.conflict_commit_ts, key_display, primary_display });
    }

    /// Log error using logz (zero allocation, structured logging)
    pub fn log_error(self: ErrWriteConflict) void {
        logz.err().ctx("WriteConflict").int("start_ts", self.start_ts).int("conflict_ts", self.conflict_ts).int("conflict_commit_ts", self.conflict_commit_ts).string("key", self.key).string("primary", self.primary).log("Write conflict detected");
    }
};

/// Check if error is ErrWriteConflict
pub fn isErrWriteConflict(err: anyerror) bool {
    _ = err;
    // In Zig, we'd typically use error unions or tagged unions for this
    // This is a placeholder - actual implementation would depend on error handling strategy
    return false;
}

/// Check if error is ErrKeyExist
pub fn isErrKeyExist(err: anyerror) bool {
    _ = err;
    // In Zig, we'd typically use error unions or tagged unions for this
    // This is a placeholder - actual implementation would depend on error handling strategy
    return false;
}

/// Create new ErrWriteConflict with arguments
pub fn newErrWriteConflictWithArgs(
    allocator: std.mem.Allocator,
    arena: *c.upb_Arena,
    start_ts: u64,
    conflict_ts: u64,
    conflict_commit_ts: u64,
    key: []const u8,
) !ErrWriteConflict {
    const conflict = c.kvrpcpb_WriteConflict_new(arena);

    c.kvrpcpb_WriteConflict_set_start_ts(conflict, start_ts);
    c.kvrpcpb_WriteConflict_set_conflict_ts(conflict, conflict_ts);
    c.kvrpcpb_WriteConflict_set_conflict_commit_ts(conflict, conflict_commit_ts);
    c.kvrpcpb_WriteConflict_set_key(conflict, c.upb_StringView{ .data = key.ptr, .size = key.len });

    return ErrWriteConflict.init(allocator, conflict);
}

/// Write conflict in latch error
pub const ErrWriteConflictInLatch = struct {
    start_ts: u64,
    conflict_ts: u64,
    key: []const u8,

    pub fn init(start_ts: u64, conflict_ts: u64, key: []const u8) ErrWriteConflictInLatch {
        return ErrWriteConflictInLatch{ .start_ts = start_ts, .conflict_ts = conflict_ts, .key = key };
    }

    pub fn format(self: ErrWriteConflictInLatch, writer: anytype) !void {
        const key_display = if (self.key.len > 0) self.key else "<empty>";
        try writer.print("write conflict in latch, startTS: {}, conflictTS: {}, key: {s}", .{ self.start_ts, self.conflict_ts, key_display });
    }

    pub fn error_string(self: ErrWriteConflictInLatch, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    /// More performant: format into provided buffer (no allocation)
    pub fn format_to_buffer(self: ErrWriteConflictInLatch, buf: []u8) ![]u8 {
        const key_display = if (self.key.len > 0) self.key else "<empty>";
        return std.fmt.bufPrint(buf, "write conflict in latch, startTS: {}, conflictTS: {}, key: {s}", .{ self.start_ts, self.conflict_ts, key_display });
    }

    /// Log error using logz (zero allocation, structured logging)
    pub fn log_error(self: ErrWriteConflictInLatch) void {
        logz.err().ctx("WriteConflictInLatch").int("start_ts", self.start_ts).int("conflict_ts", self.conflict_ts).string("key", self.key).log("Write conflict in latch detected");
    }
};

/// Retryable error wrapper
pub const ErrRetryable = struct {
    retryable: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, retryable: []const u8) !ErrRetryable {
        const owned_msg = try allocator.dupe(u8, retryable);
        return ErrRetryable{
            .retryable = owned_msg,
            .allocator = allocator,
        };
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

    /// More performant: format into provided buffer (no allocation)
    pub fn format_to_buffer(self: ErrRetryable, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "{s}", .{self.retryable});
    }

    /// Log error using logz (zero allocation, structured logging)
    pub fn log_error(self: ErrRetryable) void {
        logz.err().ctx("Retryable").string("message", self.retryable).log("Retryable error occurred");
    }
};

/// Transaction too large error
pub const ErrTxnTooLarge = struct {
    size: usize,

    pub fn init(size: usize) ErrTxnTooLarge {
        return ErrTxnTooLarge{ .size = size };
    }

    pub fn format(self: ErrTxnTooLarge, writer: anytype) !void {
        try writer.print("txn too large, size: {}.", .{self.size});
    }

    pub fn error_string(self: ErrTxnTooLarge, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    /// More performant: format into provided buffer (no allocation)
    pub fn format_to_buffer(self: ErrTxnTooLarge, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "txn too large, size: {}.", .{self.size});
    }

    /// Log error using logz (zero allocation, structured logging)
    pub fn log_error(self: ErrTxnTooLarge) void {
        logz.err().ctx("TxnTooLarge").int("size", self.size).log("Transaction too large");
    }
};

/// Entry too large error
pub const ErrEntryTooLarge = struct {
    limit: u64,
    size: u64,

    pub fn init(limit: u64, size: u64) ErrEntryTooLarge {
        return ErrEntryTooLarge{ .limit = limit, .size = size };
    }

    pub fn format(self: ErrEntryTooLarge, writer: anytype) !void {
        try writer.print("entry size too large, size: {}, limit: {}.", .{ self.size, self.limit });
    }

    pub fn error_string(self: ErrEntryTooLarge, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    /// More performant: format into provided buffer (no allocation)
    pub fn format_to_buffer(self: ErrEntryTooLarge, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "entry size too large, size: {}, limit: {}.", .{ self.size, self.limit });
    }

    /// Log error using logz (zero allocation, structured logging)
    pub fn log_error(self: ErrEntryTooLarge) void {
        logz.err().ctx("EntryTooLarge").int("size", self.size).int("limit", self.limit).log("Entry size too large");
    }
};

/// PD server timeout error
pub const ErrPDServerTimeout = struct {
    msg: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, msg: []const u8) !ErrPDServerTimeout {
        const owned_msg = try allocator.dupe(u8, msg);
        return ErrPDServerTimeout{
            .msg = owned_msg,
            .allocator = allocator,
        };
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

    /// More performant: format into provided buffer (no allocation)
    pub fn format_to_buffer(self: ErrPDServerTimeout, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "{s}", .{self.msg});
    }

    /// Log error using logz (zero allocation, structured logging)
    pub fn log_error(self: ErrPDServerTimeout) void {
        logz.err().ctx("PDServerTimeout").string("message", self.msg).log("PD server timeout occurred");
    }
};

/// GC too early error
pub const ErrGCTooEarly = struct {
    txn_start_ts: i64,
    gc_safe_point: i64,

    pub fn init(txn_start_ts: i64, gc_safe_point: i64) ErrGCTooEarly {
        return ErrGCTooEarly{
            .txn_start_ts = txn_start_ts,
            .gc_safe_point = gc_safe_point,
        };
    }

    pub fn format(self: ErrGCTooEarly, writer: anytype) !void {
        try writer.print("GC life time is shorter than transaction duration, transaction starts at {}, GC safe point is {}", .{ self.txn_start_ts, self.gc_safe_point });
    }

    pub fn error_string(self: ErrGCTooEarly, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    /// More performant: format into provided buffer (no allocation)
    pub fn format_to_buffer(self: ErrGCTooEarly, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "GC life time is shorter than transaction duration, transaction starts at {}, GC safe point is {}", .{ self.txn_start_ts, self.gc_safe_point });
    }

    /// Log error using logz (zero allocation, structured logging)
    pub fn log_error(self: ErrGCTooEarly) void {
        logz.err().ctx("GCTooEarly").int("txn_start_ts", self.txn_start_ts).int("gc_safe_point", self.gc_safe_point).log("GC too early error");
    }
};

/// Token limit error
pub const ErrTokenLimit = struct {
    store_id: u64,

    pub fn init(store_id: u64) ErrTokenLimit {
        return ErrTokenLimit{ .store_id = store_id };
    }

    pub fn format(self: ErrTokenLimit, writer: anytype) !void {
        try writer.print("Store token is up to the limit, store id = {}", .{self.store_id});
    }

    pub fn error_string(self: ErrTokenLimit, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    /// More performant: format into provided buffer (no allocation)
    pub fn format_to_buffer(self: ErrTokenLimit, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "Store token is up to the limit, store id = {}", .{self.store_id});
    }

    /// Log error using logz (zero allocation, structured logging)
    pub fn log_error(self: ErrTokenLimit) void {
        logz.err().ctx("TokenLimit").int("store_id", self.store_id).log("Store token limit reached");
    }
};

/// Assertion failed error wrapper
pub const ErrAssertionFailed = struct {
    assertion_failed: *c.kvrpcpb_AssertionFailed,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, assertion_failed: *c.kvrpcpb_AssertionFailed) ErrAssertionFailed {
        return ErrAssertionFailed{
            .assertion_failed = assertion_failed,
            .allocator = allocator,
        };
    }

    pub fn format(self: ErrAssertionFailed, writer: anytype) !void {
        // Extract assertion information from protobuf
        const start_ts = c.kvrpcpb_AssertionFailed_start_ts(self.assertion_failed);
        const key = c.kvrpcpb_AssertionFailed_key(self.assertion_failed);
        const assertion = c.kvrpcpb_AssertionFailed_assertion(self.assertion_failed);

        const key_str = if (key.size > 0) key.data[0..key.size] else "<empty>";
        try writer.print("assertion failed: start_ts={}, key={s}, assertion={}", .{ start_ts, key_str, assertion });
    }

    pub fn error_string(self: ErrAssertionFailed, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    /// More performant: format into provided buffer (no allocation)
    pub fn format_to_buffer(self: ErrAssertionFailed, buf: []u8) ![]u8 {
        const start_ts = c.kvrpcpb_AssertionFailed_start_ts(self.assertion_failed);
        const key = c.kvrpcpb_AssertionFailed_key(self.assertion_failed);
        const assertion = c.kvrpcpb_AssertionFailed_assertion(self.assertion_failed);
        const key_str = if (key.size > 0) key.data[0..key.size] else "<empty>";
        return std.fmt.bufPrint(buf, "assertion failed: start_ts={}, key={s}, assertion={}", .{ start_ts, key_str, assertion });
    }

    /// Log error using logz (zero allocation, structured logging)
    pub fn log_error(self: ErrAssertionFailed) void {
        const start_ts = c.kvrpcpb_AssertionFailed_start_ts(self.assertion_failed);
        const key = c.kvrpcpb_AssertionFailed_key(self.assertion_failed);
        const assertion = c.kvrpcpb_AssertionFailed_assertion(self.assertion_failed);
        const key_str = if (key.size > 0) key.data[0..key.size] else "<empty>";
        logz.err().ctx("AssertionFailed").int("start_ts", start_ts).string("key", key_str).int("assertion", assertion).log("Assertion failed");
    }
};

/// Extract key error from protobuf and return appropriate error instance
pub const KeyErrorResult = union(enum) {
    write_conflict: ErrWriteConflict,
    retryable: ErrRetryable,
    not_found: void,
    already_exist: ErrKeyExist,
    deadlock: ErrDeadlock,
    commit_ts_too_large: ErrCommitTsTooLarge,
    unknown: void,
};

pub fn extractKeyErr(allocator: std.mem.Allocator, key_err: *c.kvrpcpb_KeyError) !KeyErrorResult {
    // Check for write conflict
    if (c.kvrpcpb_KeyError_has_conflict(key_err)) {
        const conflict = c.kvrpcpb_KeyError_conflict(key_err);
        const write_conflict = ErrWriteConflict.init(allocator, conflict);
        logz.info().ctx("ExtractKeyErr").log("Write conflict detected");
        return KeyErrorResult{ .write_conflict = write_conflict };
    }

    // Check for retryable error
    const retryable = c.kvrpcpb_KeyError_retryable(key_err);
    if (retryable.size > 0) {
        const retryable_str = retryable.data[0..retryable.size];
        const err = try ErrRetryable.init(allocator, retryable_str);
        logz.info().ctx("ExtractKeyErr").log("Retryable error detected");
        return KeyErrorResult{ .retryable = err };
    }

    // Check for abort error
    const abort = c.kvrpcpb_KeyError_abort(key_err);
    if (abort.size > 0) {
        logz.info().ctx("ExtractKeyErr").log("Abort error detected");
        return KeyErrorResult{ .unknown = {} };
    }

    // Check for not found error
    if (c.kvrpcpb_KeyError_has_txn_not_found(key_err)) {
        logz.info().ctx("ExtractKeyErr").log("Not found error detected");
        return KeyErrorResult{ .not_found = {} };
    }

    // Check for already exist error
    if (c.kvrpcpb_KeyError_has_already_exist(key_err)) {
        const already_exist = c.kvrpcpb_KeyError_already_exist(key_err);
        const key_exist_err = ErrKeyExist.init(allocator, already_exist);
        logz.info().ctx("ExtractKeyErr").log("Already exist error detected");
        return KeyErrorResult{ .already_exist = key_exist_err };
    }

    // Check for deadlock error
    if (c.kvrpcpb_KeyError_has_deadlock(key_err)) {
        const deadlock = c.kvrpcpb_KeyError_deadlock(key_err);
        const deadlock_err = ErrDeadlock.init(allocator, deadlock, false); // Default to non-retryable
        logz.info().ctx("ExtractKeyErr").log("Deadlock error detected");
        return KeyErrorResult{ .deadlock = deadlock_err };
    }

    // Check for commit TS too large
    if (c.kvrpcpb_KeyError_has_commit_ts_too_large(key_err)) {
        const commit_ts_too_large = c.kvrpcpb_KeyError_commit_ts_too_large(key_err);
        const commit_ts_err = ErrCommitTsTooLarge.init(allocator, commit_ts_too_large);
        logz.info().ctx("ExtractKeyErr").log("Commit TS too large error detected");
        return KeyErrorResult{ .commit_ts_too_large = commit_ts_err };
    }

    logz.info().ctx("ExtractKeyErr").log("Unknown key error");
    return KeyErrorResult{ .unknown = {} };
}

/// Check if error is not found
pub fn isErrNotFound(err: TiKVError) bool {
    return err == TiKVError.NotExist;
}

/// Check if error is undetermined
pub fn isErrorUndetermined(err: TiKVError) bool {
    return err == TiKVError.ResultUndetermined;
}

/// Log TiKV error
pub fn logError(e: anyerror) void {
    if (@import("builtin").is_test) {
        std.debug.print("TiKV Error: {}\n", .{e});
    } else {
        logz.err().ctx("TiKVError").err(e).log("Encountered error");
    }
}

/// Helper function to format KeyErrorResult for display
pub fn formatKeyErrorResult(result: KeyErrorResult, allocator: std.mem.Allocator) ![]u8 {
    return switch (result) {
        .write_conflict => |wc| wc.error_string(allocator),
        .retryable => |r| r.error_string(allocator),
        .not_found => allocator.dupe(u8, "not found"),
        .already_exist => |ae| ae.error_string(allocator),
        .deadlock => |dl| dl.error_string(allocator),
        .commit_ts_too_large => |cts| cts.error_string(allocator),
        .unknown => allocator.dupe(u8, "unknown error"),
    };
}

/// Helper function to cleanup KeyErrorResult
pub fn deinitKeyErrorResult(result: *KeyErrorResult) void {
    switch (result.*) {
        .retryable => |*r| r.deinit(),
        else => {}, // Other variants don't need cleanup
    }
}

// Tests
test "error creation and formatting" {
    const allocator = std.testing.allocator;

    // Test ErrTxnTooLarge - this demonstrates proper error formatting like Go's d.Deadlock.String()
    const txn_err = ErrTxnTooLarge.init(1024);
    var buf: [512]u8 = undefined;

    // Test the format function directly (equivalent to Go's Error() method)
    var stream = std.io.fixedBufferStream(buf[0..]);
    try txn_err.format(stream.writer());
    const formatted_direct = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, formatted_direct, "txn too large") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted_direct, "1024") != null);

    // Test ErrEntryTooLarge - init(limit, size) but format shows size first, then limit
    const entry_err = ErrEntryTooLarge.init(512, 1024);
    stream.reset();
    try entry_err.format(stream.writer());
    const formatted2 = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, formatted2, "entry size too large") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted2, "size: 1024") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted2, "limit: 512") != null);

    // Test ErrWriteConflictInLatch - shows actual data extraction
    const latch_err = ErrWriteConflictInLatch.init(100, 200, "test_key");
    stream.reset();
    try latch_err.format(stream.writer());
    const formatted4 = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, formatted4, "write conflict in latch") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted4, "test_key") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted4, "startTS: 100") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted4, "conflictTS: 200") != null);

    // Test error_string methods (equivalent to Go's Error() -> string conversion)
    const txn_str = try txn_err.error_string(allocator);
    defer allocator.free(txn_str);
    try std.testing.expect(std.mem.indexOf(u8, txn_str, "txn too large") != null);

    // Test new performance methods
    // Test format_to_buffer (no allocation)
    var format_buf: [256]u8 = undefined;
    const buf_result = try txn_err.format_to_buffer(format_buf[0..]);
    try std.testing.expect(std.mem.indexOf(u8, buf_result, "txn too large") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf_result, "1024") != null);

    // Test log_error (just ensure it doesn't crash)
    txn_err.log_error();
    entry_err.log_error();
    latch_err.log_error();
}

test "error formatting and checking" {
    const allocator = std.testing.allocator;

    try std.testing.expect(isErrNotFound(TiKVError.NotExist));
    try std.testing.expect(!isErrNotFound(TiKVError.Unknown));

    try std.testing.expect(isErrorUndetermined(TiKVError.ResultUndetermined));
    try std.testing.expect(!isErrorUndetermined(TiKVError.Unknown));

    // Test retryable error with proper cleanup - demonstrates actual message extraction
    var retryable_err = try ErrRetryable.init(allocator, "test retryable message");
    defer retryable_err.deinit();

    var buf: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(buf[0..]);
    try retryable_err.format(stream.writer());
    const formatted = stream.getWritten();
    try std.testing.expectEqualStrings("test retryable message", formatted);

    // Test PD server timeout error - shows proper string handling
    var pd_timeout = try ErrPDServerTimeout.init(allocator, "PD timeout occurred");
    defer pd_timeout.deinit();

    stream.reset();
    try pd_timeout.format(stream.writer());
    const pd_formatted = stream.getWritten();
    try std.testing.expectEqualStrings("PD timeout occurred", pd_formatted);
}

test "write conflict error details" {
    const allocator = std.testing.allocator;

    // Test ErrWriteConflict with actual conflict details (like Go's WriteConflict.String())
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

    // Verify all conflict details are present (equivalent to Go's detailed error string)
    try std.testing.expect(std.mem.indexOf(u8, formatted, "write conflict") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "12345") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "67890") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "11111") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "conflicted_key") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "primary_key") != null);
}
