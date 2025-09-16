// TiKV client Zig - metrics/shortcuts (parity with client-go/metrics/shortcuts.go)
const std = @import("std");
const labels = @import("labels.zig");
const tc = @import("tikv_client.zig");

// ---- Txn cmd histograms ----
pub fn txnCmdCommitObserve(seconds: f64) !void { try tc.metrics.TiKVTxnCmdHistogram.observe(.{ .kind = labels.LblCommit }, seconds); }
pub fn txnCmdRollbackObserve(seconds: f64) !void { try tc.metrics.TiKVTxnCmdHistogram.observe(.{ .kind = labels.LblRollback }, seconds); }
pub fn txnCmdBatchGetObserve(seconds: f64) !void { try tc.metrics.TiKVTxnCmdHistogram.observe(.{ .kind = labels.LblBatchGet }, seconds); }
pub fn txnCmdGetObserve(seconds: f64) !void { try tc.metrics.TiKVTxnCmdHistogram.observe(.{ .kind = labels.LblGet }, seconds); }
pub fn txnCmdLockKeysObserve(seconds: f64) !void { try tc.metrics.TiKVTxnCmdHistogram.observe(.{ .kind = labels.LblLockKeys }, seconds); }

// ---- Rawkv cmd histograms ----
pub fn rawkvGetObserve(seconds: f64) !void { try tc.metrics.TiKVRawkvCmdHistogram.observe(.{ .kind = "get" }, seconds); }
pub fn rawkvBatchGetObserve(seconds: f64) !void { try tc.metrics.TiKVRawkvCmdHistogram.observe(.{ .kind = "batch_get" }, seconds); }
pub fn rawkvBatchPutObserve(seconds: f64) !void { try tc.metrics.TiKVRawkvCmdHistogram.observe(.{ .kind = "batch_put" }, seconds); }
pub fn rawkvDeleteObserve(seconds: f64) !void { try tc.metrics.TiKVRawkvCmdHistogram.observe(.{ .kind = "delete" }, seconds); }
pub fn rawkvBatchDeleteObserve(seconds: f64) !void { try tc.metrics.TiKVRawkvCmdHistogram.observe(.{ .kind = "batch_delete" }, seconds); }
pub fn rawkvRawScanObserve(seconds: f64) !void { try tc.metrics.TiKVRawkvCmdHistogram.observe(.{ .kind = "raw_scan" }, seconds); }
pub fn rawkvRawReverseScanObserve(seconds: f64) !void { try tc.metrics.TiKVRawkvCmdHistogram.observe(.{ .kind = "raw_reverse_scan" }, seconds); }

// ---- Rawkv size histograms ----
pub fn rawkvSizeKeyObserve(bytes: f64) !void { try tc.metrics.TiKVRawkvSizeHistogram.observe(.{ .kind = "key" }, bytes); }
pub fn rawkvSizeValueObserve(bytes: f64) !void { try tc.metrics.TiKVRawkvSizeHistogram.observe(.{ .kind = "value" }, bytes); }

// ---- Backoff histograms ----
pub fn backoffRPCObserve(seconds: f64) !void { try tc.metrics.TiKVBackoffHistogram.observe(.{ .kind = "tikvRPC" }, seconds); }
pub fn backoffLockObserve(seconds: f64) !void { try tc.metrics.TiKVBackoffHistogram.observe(.{ .kind = "txnLock" }, seconds); }
pub fn backoffLockFastObserve(seconds: f64) !void { try tc.metrics.TiKVBackoffHistogram.observe(.{ .kind = "tikvLockFast" }, seconds); }
pub fn backoffPDObserve(seconds: f64) !void { try tc.metrics.TiKVBackoffHistogram.observe(.{ .kind = "pdRPC" }, seconds); }
pub fn backoffRegionMissObserve(seconds: f64) !void { try tc.metrics.TiKVBackoffHistogram.observe(.{ .kind = "regionMiss" }, seconds); }
pub fn backoffRegionSchedulingObserve(seconds: f64) !void { try tc.metrics.TiKVBackoffHistogram.observe(.{ .kind = "regionScheduling" }, seconds); }
pub fn backoffServerBusyObserve(seconds: f64) !void { try tc.metrics.TiKVBackoffHistogram.observe(.{ .kind = "serverBusy" }, seconds); }
pub fn backoffTiKVDiskFullObserve(seconds: f64) !void { try tc.metrics.TiKVBackoffHistogram.observe(.{ .kind = "tikvDiskFull" }, seconds); }
pub fn backoffStaleCmdObserve(seconds: f64) !void { try tc.metrics.TiKVBackoffHistogram.observe(.{ .kind = "staleCommand" }, seconds); }
pub fn backoffDataNotReadyObserve(seconds: f64) !void { try tc.metrics.TiKVBackoffHistogram.observe(.{ .kind = "dataNotReady" }, seconds); }
pub fn backoffEmptyObserve(seconds: f64) !void { try tc.metrics.TiKVBackoffHistogram.observe(.{ .kind = "" }, seconds); }

// ---- Txn regions number ----
pub fn txnRegionsNumSnapshotObserve(v: f64) !void { try tc.metrics.TiKVTxnRegionsNumHistogram.observe(.{ .kind = "snapshot" }, v); }
pub fn txnRegionsNumPrewriteObserve(v: f64) !void { try tc.metrics.TiKVTxnRegionsNumHistogram.observe(.{ .kind = "2pc_prewrite" }, v); }
pub fn txnRegionsNumCommitObserve(v: f64) !void { try tc.metrics.TiKVTxnRegionsNumHistogram.observe(.{ .kind = "2pc_commit" }, v); }
pub fn txnRegionsNumCleanupObserve(v: f64) !void { try tc.metrics.TiKVTxnRegionsNumHistogram.observe(.{ .kind = "2pc_cleanup" }, v); }
pub fn txnRegionsNumPessimisticLockObserve(v: f64) !void { try tc.metrics.TiKVTxnRegionsNumHistogram.observe(.{ .kind = "2pc_pessimistic_lock" }, v); }
pub fn txnRegionsNumPessimisticRollbackObserve(v: f64) !void { try tc.metrics.TiKVTxnRegionsNumHistogram.observe(.{ .kind = "2pc_pessimistic_rollback" }, v); }
pub fn txnRegionsNumCoprocessorObserve(v: f64) !void { try tc.metrics.TiKVTxnRegionsNumHistogram.observe(.{ .kind = "coprocessor" }, v); }
pub fn txnRegionsNumBatchCoprocessorObserve(v: f64) !void { try tc.metrics.TiKVTxnRegionsNumHistogram.observe(.{ .kind = "batch_coprocessor" }, v); }

// ---- LockResolver counters ----
pub fn incLockResolverBatchResolve() !void { try tc.metrics.TiKVLockResolverCounter.incr(.{ .kind = "batch_resolve" }); }
pub fn incLockResolverExpired() !void { try tc.metrics.TiKVLockResolverCounter.incr(.{ .kind = "expired" }); }
pub fn incLockResolverNotExpired() !void { try tc.metrics.TiKVLockResolverCounter.incr(.{ .kind = "not_expired" }); }
pub fn incLockResolverWaitExpired() !void { try tc.metrics.TiKVLockResolverCounter.incr(.{ .kind = "wait_expired" }); }
pub fn incLockResolverResolve() !void { try tc.metrics.TiKVLockResolverCounter.incr(.{ .kind = "resolve" }); }
pub fn incLockResolverResolveForWrite() !void { try tc.metrics.TiKVLockResolverCounter.incr(.{ .kind = "resolve_for_write" }); }
pub fn incLockResolverResolveAsync() !void { try tc.metrics.TiKVLockResolverCounter.incr(.{ .kind = "resolve_async_commit" }); }
pub fn incLockResolverWriteConflict() !void { try tc.metrics.TiKVLockResolverCounter.incr(.{ .kind = "write_conflict" }); }
pub fn incLockResolverQueryTxnStatus() !void { try tc.metrics.TiKVLockResolverCounter.incr(.{ .kind = "query_txn_status" }); }
pub fn incLockResolverQueryTxnStatusCommitted() !void { try tc.metrics.TiKVLockResolverCounter.incr(.{ .kind = "query_txn_status_committed" }); }
pub fn incLockResolverQueryTxnStatusRolledBack() !void { try tc.metrics.TiKVLockResolverCounter.incr(.{ .kind = "query_txn_status_rolled_back" }); }
pub fn incLockResolverQueryCheckSecondaryLocks() !void { try tc.metrics.TiKVLockResolverCounter.incr(.{ .kind = "query_check_secondary_locks" }); }
pub fn incLockResolverResolveLocks() !void { try tc.metrics.TiKVLockResolverCounter.incr(.{ .kind = "query_resolve_locks" }); }
pub fn incLockResolverResolveLockLite() !void { try tc.metrics.TiKVLockResolverCounter.incr(.{ .kind = "query_resolve_lock_lite" }); }

// ---- Region cache counters ----
pub fn incRegionCacheInvalidateRegionFromCacheOK() !void { try tc.metrics.TiKVRegionCacheCounter.incr(.{ .kind = "invalidate_region_from_cache", .result = "ok" }); }
pub fn incRegionCacheSendFail() !void { try tc.metrics.TiKVRegionCacheCounter.incr(.{ .kind = "send_fail", .result = "ok" }); }
pub fn incRegionCacheGetRegionByIDOK() !void { try tc.metrics.TiKVRegionCacheCounter.incr(.{ .kind = "get_region_by_id", .result = "ok" }); }
pub fn incRegionCacheGetRegionByIDError() !void { try tc.metrics.TiKVRegionCacheCounter.incr(.{ .kind = "get_region_by_id", .result = "err" }); }
pub fn incRegionCacheGetRegionOK() !void { try tc.metrics.TiKVRegionCacheCounter.incr(.{ .kind = "get_region", .result = "ok" }); }
pub fn incRegionCacheGetRegionError() !void { try tc.metrics.TiKVRegionCacheCounter.incr(.{ .kind = "get_region", .result = "err" }); }
pub fn incRegionCacheScanRegionsOK() !void { try tc.metrics.TiKVRegionCacheCounter.incr(.{ .kind = "scan_regions", .result = "ok" }); }
pub fn incRegionCacheScanRegionsError() !void { try tc.metrics.TiKVRegionCacheCounter.incr(.{ .kind = "scan_regions", .result = "err" }); }
pub fn incRegionCacheGetStoreOK() !void { try tc.metrics.TiKVRegionCacheCounter.incr(.{ .kind = "get_store", .result = "ok" }); }
pub fn incRegionCacheGetStoreError() !void { try tc.metrics.TiKVRegionCacheCounter.incr(.{ .kind = "get_store", .result = "err" }); }
pub fn incRegionCacheInvalidateStoreRegionsOK() !void { try tc.metrics.TiKVRegionCacheCounter.incr(.{ .kind = "invalidate_store_regions", .result = "ok" }); }

// ---- Txn heartbeat ----
pub fn txnHeartBeatOKObserve(seconds: f64) !void { try tc.metrics.TiKVTxnHeartBeatHistogram.observe(.{ .kind = "ok" }, seconds); }
pub fn txnHeartBeatErrorObserve(seconds: f64) !void { try tc.metrics.TiKVTxnHeartBeatHistogram.observe(.{ .kind = "err" }, seconds); }

// ---- Status counters ----
pub fn incStatusOK() !void { try tc.metrics.TiKVStatusCounter.incr(.{ .result = "ok" }); }
pub fn incStatusError() !void { try tc.metrics.TiKVStatusCounter.incr(.{ .result = "err" }); }

// ---- Secondary lock cleanup failure counters ----
pub fn incSecondaryLockCleanupCommit() !void { try tc.metrics.TiKVSecondaryLockCleanupFailureCounter.incr(.{ .kind = "commit" }); }
pub fn incSecondaryLockCleanupRollback() !void { try tc.metrics.TiKVSecondaryLockCleanupFailureCounter.incr(.{ .kind = "rollback" }); }

// ---- Txn counters ----
pub fn incTwoPCTxnOk() !void { try tc.metrics.TiKVTwoPCTxnCounter.incr(.{ .kind = "ok" }); }
pub fn incTwoPCTxnError() !void { try tc.metrics.TiKVTwoPCTxnCounter.incr(.{ .kind = "err" }); }

pub fn incAsyncCommitTxnOk() !void { try tc.metrics.TiKVAsyncCommitTxnCounter.incr(.{ .kind = "ok" }); }
pub fn incAsyncCommitTxnError() !void { try tc.metrics.TiKVAsyncCommitTxnCounter.incr(.{ .kind = "err" }); }

pub fn incOnePCTxnOk() !void { try tc.metrics.TiKVOnePCTxnCounter.incr(.{ .kind = "ok" }); }
pub fn incOnePCTxnError() !void { try tc.metrics.TiKVOnePCTxnCounter.incr(.{ .kind = "err" }); }
pub fn incOnePCTxnFallback() !void { try tc.metrics.TiKVOnePCTxnCounter.incr(.{ .kind = "fallback" }); }

// ---- Batch recv histogram ----
pub fn batchRecvOkObserve(seconds: f64) !void { try tc.metrics.TiKVBatchRecvLatency.observe(.{ .result = "ok" }, seconds); }
pub fn batchRecvErrorObserve(seconds: f64) !void { try tc.metrics.TiKVBatchRecvLatency.observe(.{ .result = "err" }, seconds); }

// ---- Prewrite assertion usage ----
pub fn incPrewriteAssertionNone() !void { try tc.metrics.TiKVPrewriteAssertionUsageCounter.incr(.{ .kind = "none" }); }
pub fn incPrewriteAssertionExist() !void { try tc.metrics.TiKVPrewriteAssertionUsageCounter.incr(.{ .kind = "exist" }); }
pub fn incPrewriteAssertionNotExist() !void { try tc.metrics.TiKVPrewriteAssertionUsageCounter.incr(.{ .kind = "not-exist" }); }
pub fn incPrewriteAssertionUnknown() !void { try tc.metrics.TiKVPrewriteAssertionUsageCounter.incr(.{ .kind = "unknown" }); }

// ---- Minimal test ----
test "shortcuts basic calls" {
    const gpa = std.testing.allocator;
    try tc.InitMetrics(gpa, .{});
    defer tc.DeinitMetrics();
    try txnCmdCommitObserve(0.002);
    try incTwoPCTxnOk();
}
