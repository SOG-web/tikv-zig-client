// TiKV client Zig - metrics/tikv_client
// Prometheus-style metrics implemented using karlseguin/metrics.zig
const std = @import("std");
const m = @import("metrics");
const labels = @import("labels.zig");

// ---------------- Label structs ----------------
// Note: 'type' label in Go is mapped to 'kind' here due to Zig reserved keyword.

pub const LKind = struct { kind: []const u8 };
pub const LKindStoreStale = struct { kind: []const u8, store: []const u8, stale_read: []const u8 };
pub const LStoreStale = struct { store: []const u8, stale_read: []const u8 };
pub const LKindResult = struct { kind: []const u8, result: []const u8 };
pub const LResult = struct { result: []const u8 };
pub const LStore = struct { store: []const u8 };
pub const LAddrStore = struct { address: []const u8, store: []const u8 };
pub const LFromToKindResult = struct { from_store: []const u8, to_store: []const u8, kind: []const u8, result: []const u8 };

// ---------------- Buckets ----------------
// Define comptime bucket arrays matching client-go values.

pub const BKT_0p5ms_2x_29 = blk: {
    var a: [29]f64 = undefined; var v: f64 = 0.0005; var i: usize = 0; while (i < a.len) : (i += 1) { a[i] = v; v *= 2; }
    break :blk a;
};
pub const BKT_1_4x_17 = blk: { var a: [17]f64 = undefined; var v: f64 = 1; var i: usize = 0; while (i < a.len) : (i += 1) { a[i] = v; v *= 4; } break :blk a; };
pub const BKT_16B_4x_17 = blk: { var a: [17]f64 = undefined; var v: f64 = 16; var i: usize = 0; while (i < a.len) : (i += 1) { a[i] = v; v *= 4; } break :blk a; };
pub const BKT_1_2x_25 = blk: { var a: [25]f64 = undefined; var v: f64 = 1; var i: usize = 0; while (i < a.len) : (i += 1) { a[i] = v; v *= 2; } break :blk a; };
pub const BKT_1B_2x_30 = blk: { var a: [30]f64 = undefined; var v: f64 = 1; var i: usize = 0; while (i < a.len) : (i += 1) { a[i] = v; v *= 2; } break :blk a; };
pub const BKT_1ns_2x_34 = blk: { var a: [34]f64 = undefined; var v: f64 = 1; var i: usize = 0; while (i < a.len) : (i += 1) { a[i] = v; v *= 2; } break :blk a; };
pub const BKT_1us_2x_34 = blk: { var a: [34]f64 = undefined; var v: f64 = 1000; var i: usize = 0; while (i < a.len) : (i += 1) { a[i] = v; v *= 2; } break :blk a; };
pub const BKT_1ms_2x_20 = blk: { var a: [20]f64 = undefined; var v: f64 = 0.001; var i: usize = 0; while (i < a.len) : (i += 1) { a[i] = v; v *= 2; } break :blk a; };
pub const BKT_1ms_2x_28 = blk: { var a: [28]f64 = undefined; var v: f64 = 0.0005; var i: usize = 0; while (i < a.len) : (i += 1) { a[i] = v; v *= 2; } break :blk a; }; // 0.5ms~ per Go sli
pub const BKT_5us_2x_30 = blk: { var a: [30]f64 = undefined; var v: f64 = 0.000005; var i: usize = 0; while (i < a.len) : (i += 1) { a[i] = v; v *= 2; } break :blk a; };
pub const BKT_1ms_2x_22 = blk: { var a: [22]f64 = undefined; var v: f64 = 0.001; var i: usize = 0; while (i < a.len) : (i += 1) { a[i] = v; v *= 2; } break :blk a; };
pub const BKT_1_2x_11 = blk: { var a: [11]f64 = undefined; var v: f64 = 1; var i: usize = 0; while (i < a.len) : (i += 1) { a[i] = v; v *= 2; } break :blk a; };
pub const BKT_1_2x_12 = blk: { var a: [12]f64 = undefined; var v: f64 = 1; var i: usize = 0; while (i < a.len) : (i += 1) { a[i] = v; v *= 2; } break :blk a; };
pub const BKT_1ms_2x_24 = blk: { var a: [24]f64 = undefined; var v: f64 = 0.001; var i: usize = 0; while (i < a.len) : (i += 1) { a[i] = v; v *= 2; } break :blk a; };
pub const BKT_FIXED_RETRY = [10]f64{ 1, 2, 3, 4, 8, 16, 32, 64, 128, 256 };
pub const BKT_1MBs_2x_13 = blk: { var a: [13]f64 = undefined; var v: f64 = 1024; var i: usize = 0; while (i < a.len) : (i += 1) { a[i] = v; v *= 2; } break :blk a; };

// ---------------- Metrics struct ----------------

pub const Metrics = struct {
    // Histograms
    TiKVTxnCmdHistogram: m.HistogramVec(f64, LKind, &BKT_0p5ms_2x_29),
    TiKVBackoffHistogram: m.HistogramVec(f64, LKind, &BKT_0p5ms_2x_29),
    TiKVSendReqHistogram: m.HistogramVec(f64, LKindStoreStale, &BKT_0p5ms_2x_29),
    TiKVCoprocessorHistogram: m.HistogramVec(f64, LStoreStale, &BKT_0p5ms_2x_29),
    TiKVTxnWriteKVCountHistogram: m.Histogram(f64, &BKT_1_4x_17),
    TiKVTxnWriteSizeHistogram: m.Histogram(f64, &BKT_16B_4x_17),
    TiKVRawkvCmdHistogram: m.HistogramVec(f64, LKind, &BKT_0p5ms_2x_29),
    TiKVRawkvSizeHistogram: m.HistogramVec(f64, LKind, &BKT_1B_2x_30),
    TiKVTxnRegionsNumHistogram: m.HistogramVec(f64, LKind, &BKT_1_2x_25),
    TiKVLocalLatchWaitTimeHistogram: m.Histogram(f64, &BKT_1ms_2x_20),
    TiKVStatusDuration: m.HistogramVec(f64, LStore, &BKT_1ms_2x_20),
    TiKVBatchWaitDuration: m.Histogram(f64, &BKT_1ns_2x_34),
    TiKVBatchSendLatency: m.Histogram(f64, &BKT_1ns_2x_34),
    TiKVBatchRecvLatency: m.HistogramVec(f64, LResult, &BKT_1us_2x_34),
    TiKVRangeTaskPushDuration: m.HistogramVec(f64, LKind, &BKT_1ms_2x_20),
    TiKVTokenWaitDuration: m.Histogram(f64, &BKT_1ns_2x_34),
    TiKVTxnHeartBeatHistogram: m.HistogramVec(f64, LKind, &BKT_1ms_2x_20),
    TiKVPessimisticLockKeysDuration: m.Histogram(f64, &BKT_1ms_2x_24),
    TiKVTSFutureWaitDuration: m.Histogram(f64, &BKT_5us_2x_30),
    TiKVRequestRetryTimesHistogram: m.Histogram(f64, &BKT_FIXED_RETRY),
    TiKVTxnCommitBackoffSeconds: m.Histogram(f64, &BKT_1ms_2x_22),
    TiKVTxnCommitBackoffCount: m.Histogram(f64, &BKT_1_2x_12),
    TiKVSmallReadDuration: m.Histogram(f64, &BKT_1ms_2x_28),
    TiKVReadThroughput: m.Histogram(f64, &BKT_1MBs_2x_13),

    // Counters/Gauges
    TiKVLockResolverCounter: m.CounterVec(u64, LKind),
    TiKVRegionErrorCounter: m.CounterVec(u64, LKind),
    TiKVLoadSafepointCounter: m.CounterVec(u64, LKind),
    TiKVSecondaryLockCleanupFailureCounter: m.CounterVec(u64, LKind),
    TiKVRegionCacheCounter: m.CounterVec(u64, LKindResult),
    TiKVStatusCounter: m.CounterVec(u64, LResult),
    TiKVBatchWaitOverLoad: m.Counter(u64),
    TiKVBatchPendingRequests: m.HistogramVec(f64, LStore, &BKT_1_2x_11),
    TiKVBatchRequests: m.HistogramVec(f64, LStore, &BKT_1_2x_11),
    TiKVBatchClientUnavailable: m.Histogram(f64, &BKT_1ms_2x_28),
    TiKVBatchClientWaitEstablish: m.Histogram(f64, &BKT_1ms_2x_28),
    TiKVBatchClientRecycle: m.Histogram(f64, &BKT_1ms_2x_28),
    TiKVRangeTaskStats: m.GaugeVec(f64, LKindResult),
    TiKVTTLLifeTimeReachCounter: m.Counter(u64),
    TiKVNoAvailableConnectionCounter: m.Counter(u64),
    TiKVTwoPCTxnCounter: m.CounterVec(u64, LKind),
    TiKVAsyncCommitTxnCounter: m.CounterVec(u64, LKind),
    TiKVOnePCTxnCounter: m.CounterVec(u64, LKind),
    TiKVStoreLimitErrorCounter: m.CounterVec(u64, LAddrStore),
    TiKVGRPCConnTransientFailureCounter: m.CounterVec(u64, LAddrStore),
    TiKVPanicCounter: m.CounterVec(u64, LKind),
    TiKVForwardRequestCounter: m.CounterVec(u64, LFromToKindResult),
    TiKVSafeTSUpdateCounter: m.CounterVec(u64, LResult),
    TiKVMinSafeTSGapSeconds: m.GaugeVec(f64, LStore),
    TiKVReplicaSelectorFailureCounter: m.CounterVec(u64, LKind),
    TiKVUnsafeDestroyRangeFailuresCounterVec: m.CounterVec(u64, LKind),
    TiKVPrewriteAssertionUsageCounter: m.CounterVec(u64, LKind),
};

// Global metrics instance initialized to noop
pub var metrics = m.initializeNoop(Metrics);

// Internal helpers for metric names and opts
const H = m.Opts; // help option
const R = m.RegistryOpts; // registry options (prefix/exclude)

// Optional: future extension for per-metric help strings

pub fn InitMetrics(allocator: std.mem.Allocator, comptime opts: m.RegistryOpts) !void {
    metrics = .{
        .TiKVTxnCmdHistogram = try m.HistogramVec(f64, LKind, &BKT_0p5ms_2x_29).init(allocator, "txn_cmd_duration_seconds", .{ .help = "Processing time of txn cmds" }, opts),
        .TiKVBackoffHistogram = try m.HistogramVec(f64, LKind, &BKT_0p5ms_2x_29).init(allocator, "backoff_seconds", .{ .help = "Total backoff seconds of a single backoffer" }, opts),
        .TiKVSendReqHistogram = try m.HistogramVec(f64, LKindStoreStale, &BKT_0p5ms_2x_29).init(allocator, "request_seconds", .{ .help = "Sending request duration" }, opts),
        .TiKVCoprocessorHistogram = try m.HistogramVec(f64, LStoreStale, &BKT_0p5ms_2x_29).init(allocator, "cop_duration_seconds", .{ .help = "Coprocessor task run duration" }, opts),
        .TiKVTxnWriteKVCountHistogram = m.Histogram(f64, &BKT_1_4x_17).init("txn_write_kv_num", .{ .help = "Count of kv pairs to write in a txn" }, opts),
        .TiKVTxnWriteSizeHistogram = m.Histogram(f64, &BKT_16B_4x_17).init("txn_write_size_bytes", .{ .help = "Size of kv pairs to write in a txn" }, opts),
        .TiKVRawkvCmdHistogram = try m.HistogramVec(f64, LKind, &BKT_0p5ms_2x_29).init(allocator, "rawkv_cmd_seconds", .{ .help = "Processing time of rawkv cmds" }, opts),
        .TiKVRawkvSizeHistogram = try m.HistogramVec(f64, LKind, &BKT_1B_2x_30).init(allocator, "rawkv_kv_size_bytes", .{ .help = "Size of key/value to put" }, opts),
        .TiKVTxnRegionsNumHistogram = try m.HistogramVec(f64, LKind, &BKT_1_2x_25).init(allocator, "txn_regions_num", .{ .help = "Number of regions in a txn" }, opts),
        .TiKVLocalLatchWaitTimeHistogram = m.Histogram(f64, &BKT_1ms_2x_20).init("local_latch_wait_seconds", .{ .help = "Wait time of a get local latch" }, opts),
        .TiKVStatusDuration = try m.HistogramVec(f64, LStore, &BKT_1ms_2x_20).init(allocator, "kv_status_api_duration", .{ .help = "Duration for kv status api" }, opts),
        .TiKVBatchWaitDuration = m.Histogram(f64, &BKT_1ns_2x_34).init("batch_wait_duration", .{ .help = "Batch wait duration" }, opts),
        .TiKVBatchSendLatency = m.Histogram(f64, &BKT_1ns_2x_34).init("batch_send_latency", .{ .help = "Batch send latency" }, opts),
        .TiKVBatchRecvLatency = try m.HistogramVec(f64, LResult, &BKT_1us_2x_34).init(allocator, "batch_recv_latency", .{ .help = "Batch recv latency" }, opts),
        .TiKVRangeTaskPushDuration = try m.HistogramVec(f64, LKind, &BKT_1ms_2x_20).init(allocator, "range_task_push_duration", .{ .help = "Duration to push sub tasks to range task workers" }, opts),
        .TiKVTokenWaitDuration = m.Histogram(f64, &BKT_1ns_2x_34).init("batch_executor_token_wait_duration", .{ .help = "Txn token wait duration to process batches" }, opts),
        .TiKVTxnHeartBeatHistogram = try m.HistogramVec(f64, LKind, &BKT_1ms_2x_20).init(allocator, "txn_heart_beat", .{ .help = "txn_heartbeat request duration" }, opts),
        .TiKVPessimisticLockKeysDuration = m.Histogram(f64, &BKT_1ms_2x_24).init("pessimistic_lock_keys_duration", .{ .help = "Txn pessimistic lock keys duration" }, opts),
        .TiKVTSFutureWaitDuration = m.Histogram(f64, &BKT_5us_2x_30).init("ts_future_wait_seconds", .{ .help = "Waiting timestamp future" }, opts),
        .TiKVRequestRetryTimesHistogram = m.Histogram(f64, &BKT_FIXED_RETRY).init("request_retry_times", .{ .help = "How many times a region request retries" }, opts),
        .TiKVTxnCommitBackoffSeconds = m.Histogram(f64, &BKT_1ms_2x_22).init("txn_commit_backoff_seconds", .{ .help = "Total backoff duration in committing a txn" }, opts),
        .TiKVTxnCommitBackoffCount = m.Histogram(f64, &BKT_1_2x_12).init("txn_commit_backoff_count", .{ .help = "Backoff count in committing a txn" }, opts),
        .TiKVSmallReadDuration = m.Histogram(f64, &BKT_1ms_2x_28).init("tikv_small_read_duration", .{ .help = "Read time of TiKV small read" }, opts),
        .TiKVReadThroughput = m.Histogram(f64, &BKT_1MBs_2x_13).init("tikv_read_throughput", .{ .help = "Read throughput in Bytes/s" }, opts),
        .TiKVLockResolverCounter = try m.CounterVec(u64, LKind).init(allocator, "lock_resolver_actions_total", .{ .help = "Counter of lock resolver actions" }, opts),
        .TiKVRegionErrorCounter = try m.CounterVec(u64, LKind).init(allocator, "region_err_total", .{ .help = "Counter of region errors" }, opts),
        .TiKVLoadSafepointCounter = try m.CounterVec(u64, LKind).init(allocator, "load_safepoint_total", .{ .help = "Counter of load safepoint" }, opts),
        .TiKVSecondaryLockCleanupFailureCounter = try m.CounterVec(u64, LKind).init(allocator, "lock_cleanup_task_total", .{ .help = "failure statistic of secondary lock cleanup task" }, opts),
        .TiKVRegionCacheCounter = try m.CounterVec(u64, LKindResult).init(allocator, "region_cache_operations_total", .{ .help = "Counter of region cache" }, opts),
        .TiKVStatusCounter = try m.CounterVec(u64, LResult).init(allocator, "kv_status_api_count", .{ .help = "Counter of access kv status api" }, opts),
        .TiKVBatchWaitOverLoad = m.Counter(u64).init("batch_wait_overload", .{ .help = "event of tikv transport layer overload" }, opts),
        .TiKVBatchPendingRequests = try m.HistogramVec(f64, LStore, &BKT_1_2x_11).init(allocator, "batch_pending_requests", .{ .help = "number of requests pending in the batch channel" }, opts),
        .TiKVBatchRequests = try m.HistogramVec(f64, LStore, &BKT_1_2x_11).init(allocator, "batch_requests", .{ .help = "number of requests in one batch" }, opts),
        .TiKVBatchClientUnavailable = m.Histogram(f64, &BKT_1ms_2x_28).init("batch_client_unavailable_seconds", .{ .help = "batch client unavailable" }, opts),
        .TiKVBatchClientWaitEstablish = m.Histogram(f64, &BKT_1ms_2x_28).init("batch_client_wait_connection_establish", .{ .help = "batch client wait new connection establish" }, opts),
        .TiKVBatchClientRecycle = m.Histogram(f64, &BKT_1ms_2x_28).init("batch_client_reset", .{ .help = "batch client recycle connection and reconnect duration" }, opts),
        .TiKVRangeTaskStats = try m.GaugeVec(f64, LKindResult).init(allocator, "range_task_stats", .{ .help = "stat of range tasks" }, opts),
        .TiKVTTLLifeTimeReachCounter = m.Counter(u64).init("ttl_lifetime_reach_total", .{ .help = "Counter of ttlManager live too long" }, opts),
        .TiKVNoAvailableConnectionCounter = m.Counter(u64).init("batch_client_no_available_connection_total", .{ .help = "Counter of no available batch client" }, opts),
        .TiKVTwoPCTxnCounter = try m.CounterVec(u64, LKind).init(allocator, "commit_txn_counter", .{ .help = "Counter of 2PC transactions" }, opts),
        .TiKVAsyncCommitTxnCounter = try m.CounterVec(u64, LKind).init(allocator, "async_commit_txn_counter", .{ .help = "Counter of async commit transactions" }, opts),
        .TiKVOnePCTxnCounter = try m.CounterVec(u64, LKind).init(allocator, "one_pc_txn_counter", .{ .help = "Counter of 1PC transactions" }, opts),
        .TiKVStoreLimitErrorCounter = try m.CounterVec(u64, LAddrStore).init(allocator, "get_store_limit_token_error", .{ .help = "store token is up to the limit" }, opts),
        .TiKVGRPCConnTransientFailureCounter = try m.CounterVec(u64, LAddrStore).init(allocator, "connection_transient_failure_count", .{ .help = "gRPC connection transient failure" }, opts),
        .TiKVPanicCounter = try m.CounterVec(u64, LKind).init(allocator, "panic_total", .{ .help = "Counter of panic" }, opts),
        .TiKVForwardRequestCounter = try m.CounterVec(u64, LFromToKindResult).init(allocator, "forward_request_counter", .{ .help = "tikv request forwarded through another node" }, opts),
        .TiKVSafeTSUpdateCounter = try m.CounterVec(u64, LResult).init(allocator, "safets_update_counter", .{ .help = "tikv safe_ts updated" }, opts),
        .TiKVMinSafeTSGapSeconds = try m.GaugeVec(f64, LStore).init(allocator, "min_safets_gap_seconds", .{ .help = "Minimal non-zero SafeTS gap for each store" }, opts),
        .TiKVReplicaSelectorFailureCounter = try m.CounterVec(u64, LKind).init(allocator, "replica_selector_failure_counter", .{ .help = "why replica selector cannot yield a potential leader" }, opts),
        .TiKVUnsafeDestroyRangeFailuresCounterVec = try m.CounterVec(u64, LKind).init(allocator, "gc_unsafe_destroy_range_failures", .{ .help = "unsafe destroyrange failures" }, opts),
        .TiKVPrewriteAssertionUsageCounter = try m.CounterVec(u64, LKind).init(allocator, "prewrite_assertion_count", .{ .help = "assertions used in prewrite requests" }, opts),
    };
}

/// Initialize metrics with Prometheus-style namespace and subsystem prefixes.
/// Generates a prefix "{namespace}_{subsystem}_" and forwards to InitMetrics.
pub fn InitMetricsNS(
    allocator: std.mem.Allocator,
    comptime namespace: []const u8,
    comptime subsystem: []const u8,
) !void {
    const prefix = std.fmt.comptimePrint("{s}_{s}_", .{ namespace, subsystem });
    try InitMetrics(allocator, .{ .prefix = prefix });
}

pub fn RegisterMetrics() void {
    // No-op: metrics.zig uses a registry at init. Expose for parity.
}

pub fn DeinitMetrics() void {
    // Deinit all vectored metrics (they allocate); scalars are no-alloc.
    metrics.TiKVTxnCmdHistogram.deinit();
    metrics.TiKVBackoffHistogram.deinit();
    metrics.TiKVSendReqHistogram.deinit();
    metrics.TiKVCoprocessorHistogram.deinit();
    metrics.TiKVRawkvCmdHistogram.deinit();
    metrics.TiKVRawkvSizeHistogram.deinit();
    metrics.TiKVTxnRegionsNumHistogram.deinit();
    metrics.TiKVStatusDuration.deinit();
    metrics.TiKVBatchRecvLatency.deinit();
    metrics.TiKVRangeTaskPushDuration.deinit();
    metrics.TiKVTxnHeartBeatHistogram.deinit();
    metrics.TiKVBatchPendingRequests.deinit();
    metrics.TiKVBatchRequests.deinit();
    metrics.TiKVRangeTaskStats.deinit();
    metrics.TiKVMinSafeTSGapSeconds.deinit();
    metrics.TiKVLockResolverCounter.deinit();
    metrics.TiKVRegionErrorCounter.deinit();
    metrics.TiKVLoadSafepointCounter.deinit();
    metrics.TiKVSecondaryLockCleanupFailureCounter.deinit();
    metrics.TiKVRegionCacheCounter.deinit();
    metrics.TiKVStatusCounter.deinit();
    metrics.TiKVTwoPCTxnCounter.deinit();
    metrics.TiKVAsyncCommitTxnCounter.deinit();
    metrics.TiKVOnePCTxnCounter.deinit();
    metrics.TiKVStoreLimitErrorCounter.deinit();
    metrics.TiKVGRPCConnTransientFailureCounter.deinit();
    metrics.TiKVPanicCounter.deinit();
    metrics.TiKVForwardRequestCounter.deinit();
    metrics.TiKVSafeTSUpdateCounter.deinit();
    metrics.TiKVReplicaSelectorFailureCounter.deinit();
    metrics.TiKVUnsafeDestroyRangeFailuresCounterVec.deinit();
    metrics.TiKVPrewriteAssertionUsageCounter.deinit();
    // Reset to noop for safety if tests continue
    metrics = m.initializeNoop(Metrics);
}

// --------- Read helpers for tests ---------
// These helpers serialize metrics and parse simple values for assertions.

pub fn readCounterApprox(allocator: std.mem.Allocator, metric_name: []const u8) !i64 {
    var arr = std.ArrayList(u8).init(allocator);
    defer arr.deinit();
    var w = arr.writer();
    try m.write(&metrics, &w);
    const buf = arr.items;
    // very basic parse: find line starting with metric_name and parse last token as number
    if (std.mem.indexOf(u8, buf, metric_name)) |start| {
        const line_end = std.mem.indexOfScalarPos(u8, buf, start, '\n') orelse buf.len;
        const line = buf[start..line_end];
        // last token after space
        var it = std.mem.tokenizeAny(u8, line, " \t");
        var last: []const u8 = line;
        while (it.next()) |tok| last = tok;
        const val = std.fmt.parseInt(i64, last, 10) catch return -1;
        return val;
    }
    return -1;
}

// --------- SLI ---------
const smallTxnReadRow: u64 = 20;
const smallTxnReadSize: f64 = 1 * 1024 * 1024; // 1MB
pub fn ObserveReadSLI(read_keys: u64, read_time_seconds: f64, read_size_bytes: f64) void {
    if (read_keys != 0 and read_time_seconds != 0) {
        if (read_keys <= smallTxnReadRow and read_size_bytes < smallTxnReadSize) {
            metrics.TiKVSmallReadDuration.observe(read_time_seconds);
        } else {
            metrics.TiKVReadThroughput.observe(read_size_bytes / read_time_seconds);
        }
    }
}

// ---------------- Tests ----------------

test "initialize metrics and observe a few values" {
    const gpa = std.testing.allocator;
    try InitMetrics(gpa, .{});
    defer DeinitMetrics();
    try metrics.TiKVTxnCmdHistogram.observe(.{ .kind = labels.LblCommit }, 0.01);
    try metrics.TiKVTwoPCTxnCounter.incr(.{ .kind = "ok" });
    ObserveReadSLI(10, 0.1, 512.0);
}
