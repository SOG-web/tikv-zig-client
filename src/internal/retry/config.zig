// internal/retry/config.zig
// Backoff configuration and defaults, adapted from Go's internal/retry/config.go.
// No metrics dependency here.

const std = @import("std");
const kv = @import("../../kv/types.zig");
const backoffz = @import("backoff.zig");

pub const BackoffFnCfg = struct {
    base: i32,
    cap: i32,
    jitter: backoffz.Jitter,

    pub fn init(base: i32, cap: i32, jitter: backoffz.Jitter) BackoffFnCfg {
        return .{ .base = base, .cap = cap, .jitter = jitter };
    }
};

pub const Config = struct {
    name: []const u8,
    fn_cfg: BackoffFnCfg,
    //TODO: add metrics
    err_tag: []const u8 = "", // symbolic error tag similar to Go's tikverr

    pub fn init(name: []const u8, cfg: BackoffFnCfg) Config {
        return .{ .name = name, .fn_cfg = cfg };
    }

    pub fn initWithErr(name: []const u8, cfg: BackoffFnCfg, err_tag: []const u8) Config {
        return .{ .name = name, .fn_cfg = cfg, .err_tag = err_tag };
    }

    /// Create a backoff state machine; for txnLockFast we read base from kv.Variables.BackoffLockFast.
    pub fn createBackoff(self: *const Config, vars: *const kv.Variables) backoffz.Backoff {
        var base = self.fn_cfg.base;
        if (std.ascii.eqlIgnoreCase(self.name, "txnLockFast")) {
            base = vars.backoff_lock_fast;
        }
        return backoffz.Backoff.init(base, self.fn_cfg.cap, self.fn_cfg.jitter);
    }
};

// ---------------- Defaults & helpers (no metrics) ----------------

pub const txnLockFastName = "txnLockFast";

pub const BoTiKVRPC = Config.initWithErr("tikvRPC", BackoffFnCfg.init(100, 2000, .EqualJitter), "ErrTiKVServerTimeout");
pub const BoTiFlashRPC = Config.initWithErr("tiflashRPC", BackoffFnCfg.init(100, 2000, .EqualJitter), "ErrTiFlashServerTimeout");
pub const BoTxnLock = Config.initWithErr("txnLock", BackoffFnCfg.init(100, 3000, .EqualJitter), "ErrResolveLockTimeout");
pub const BoPDRPC = Config.initWithErr("pdRPC", BackoffFnCfg.init(500, 3000, .EqualJitter), "ErrPDServerTimeout");
pub const BoRegionMiss = Config.initWithErr("regionMiss", BackoffFnCfg.init(2, 500, .NoJitter), "ErrRegionUnavailable");
pub const BoRegionScheduling = Config.initWithErr("regionScheduling", BackoffFnCfg.init(2, 500, .NoJitter), "ErrRegionUnavailable");
pub const BoTiKVServerBusy = Config.initWithErr("tikvServerBusy", BackoffFnCfg.init(2000, 10000, .EqualJitter), "ErrTiKVServerBusy");
pub const BoTiKVDiskFull = Config.initWithErr("tikvDiskFull", BackoffFnCfg.init(500, 5000, .NoJitter), "ErrTiKVDiskFull");
pub const BoTiFlashServerBusy = Config.initWithErr("tiflashServerBusy", BackoffFnCfg.init(2000, 10000, .EqualJitter), "ErrTiFlashServerBusy");
pub const BoTxnNotFound = Config.initWithErr("txnNotFound", BackoffFnCfg.init(2, 500, .NoJitter), "ErrResolveLockTimeout");
pub const BoStaleCmd = Config.initWithErr("staleCommand", BackoffFnCfg.init(2, 1000, .NoJitter), "ErrTiKVStaleCommand");
pub const BoMaxTsNotSynced = Config.initWithErr("maxTsNotSynced", BackoffFnCfg.init(2, 500, .NoJitter), "ErrTiKVMaxTimestampNotSynced");
pub const BoMaxDataNotReady = Config.initWithErr("dataNotReady", BackoffFnCfg.init(100, 2000, .NoJitter), "ErrRegionDataNotReady");
pub const BoMaxRegionNotInitialized = Config.initWithErr("regionNotInitialized", BackoffFnCfg.init(2, 1000, .NoJitter), "ErrRegionNotInitialized");
pub const BoTxnLockFast = Config.initWithErr(txnLockFastName, BackoffFnCfg.init(2, 3000, .EqualJitter), "ErrResolveLockTimeout");

pub fn isSleepExcluded(name: []const u8) bool {
    return std.mem.eql(u8, name, "tikvServerBusy") or std.mem.eql(u8, name, "tiflashServerBusy");
}

// ---------------- Tests ----------------

test "config createBackoff uses vars for txnLockFast" {
    var vars = kv.defaultVariables();
    vars.backoff_lock_fast = 5;
    const cfg = Config.init("txnLockFast", BackoffFnCfg.init(100, 3000, .EqualJitter));
    try std.testing.expectEqual(@as(i32, 5), cfg.createBackoff(&vars).base);
}
