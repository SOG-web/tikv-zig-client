const std = @import("std");
const kvproto = @import("kvproto");

pub const kvrpcpb = kvproto.kvrpcpb;
pub const pdpb = kvproto.pdpb;

// Mock logz for testing environment
pub const logz = if (@import("builtin").is_test) struct {
    pub fn err() MockLogger {
        return MockLogger{};
    }
    pub fn info() MockLogger {
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
        pub fn err(self: MockLogger, _: anyerror) MockLogger {
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

pub fn isErrNotFound(err: TiKVError) bool {
    return err == TiKVError.NotExist;
}

pub fn isErrorUndetermined(err: TiKVError) bool {
    return err == TiKVError.ResultUndetermined;
}

pub fn logError(e: anyerror) void {
    if (@import("builtin").is_test) {
        std.debug.print("TiKV Error: {}\n", .{e});
    } else {
        logz.err().ctx("TiKVError").err(e).log("Encountered error");
    }
}

test "error formatting and checking - simple flags" {
    try std.testing.expect(isErrNotFound(TiKVError.NotExist));
    try std.testing.expect(!isErrNotFound(TiKVError.Unknown));

    try std.testing.expect(isErrorUndetermined(TiKVError.ResultUndetermined));
    try std.testing.expect(!isErrorUndetermined(TiKVError.Unknown));
}
