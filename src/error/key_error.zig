const std = @import("std");
const common = @import("common.zig");
const kvrpcpb = common.kvrpcpb;
const logz = common.logz;

const write_conflict_mod = @import("write_conflict.zig");
const kv_errors_mod = @import("kv_errors.zig");
const deadlock_mod = @import("deadlock.zig");

const ErrWriteConflict = write_conflict_mod.ErrWriteConflict;
const ErrRetryable = kv_errors_mod.ErrRetryable;
const ErrKeyExist = kv_errors_mod.ErrKeyExist;
const ErrDeadlock = deadlock_mod.ErrDeadlock;
const ErrCommitTsTooLarge = kv_errors_mod.ErrCommitTsTooLarge;

pub const KeyErrorResult = union(enum) {
    write_conflict: ErrWriteConflict,
    retryable: ErrRetryable,
    not_found: void,
    already_exist: ErrKeyExist,
    deadlock: ErrDeadlock,
    commit_ts_too_large: ErrCommitTsTooLarge,
    unknown: void,
};

pub fn extractKeyErr(allocator: std.mem.Allocator, key_err: *kvrpcpb.KeyError) !KeyErrorResult {
    if (key_err.conflict) |conflict| {
        const wc = ErrWriteConflict.init(allocator, conflict);
        logz.info().ctx("ExtractKeyErr").log("Write conflict detected");
        return KeyErrorResult{ .write_conflict = wc };
    }

    if (key_err.retryable.len > 0) {
        const err = try ErrRetryable.init(allocator, key_err.retryable);
        logz.info().ctx("ExtractKeyErr").log("Retryable error detected");
        return KeyErrorResult{ .retryable = err };
    }

    if (key_err.abort.len > 0) {
        logz.info().ctx("ExtractKeyErr").log("Abort error detected");
        return KeyErrorResult{ .unknown = {} };
    }

    if (key_err.txn_not_found != null) {
        logz.info().ctx("ExtractKeyErr").log("Not found error detected");
        return KeyErrorResult{ .not_found = {} };
    }

    if (key_err.already_exist) |ae| {
        const key_exist_err = ErrKeyExist.init(allocator, ae);
        logz.info().ctx("ExtractKeyErr").log("Already exist error detected");
        return KeyErrorResult{ .already_exist = key_exist_err };
    }

    if (key_err.deadlock) |dl| {
        const deadlock_err = ErrDeadlock.init(allocator, dl, false);
        logz.info().ctx("ExtractKeyErr").log("Deadlock error detected");
        return KeyErrorResult{ .deadlock = deadlock_err };
    }

    if (key_err.commit_ts_too_large) |cts| {
        logz.info().ctx("ExtractKeyErr").log("Commit TS too large error detected");
        return KeyErrorResult{ .commit_ts_too_large = ErrCommitTsTooLarge.init(allocator, cts.commit_ts) };
    }

    logz.info().ctx("ExtractKeyErr").log("Unknown key error");
    return KeyErrorResult{ .unknown = {} };
}

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

pub fn deinitKeyErrorResult(result: *KeyErrorResult) void {
    switch (result.*) {
        .retryable => |*r| r.deinit(),
        else => {},
    }
}

pub fn isErrKeyExist(err: anyerror) bool {
    _ = err;
    return false;
}
