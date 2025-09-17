const std = @import("std");
const kvproto = @import("kvproto");
const kvrpcpb = kvproto.kvrpcpb;
const coprocessor = kvproto.coprocessor;
const mpp = kvproto.mpp;
const debugpb = kvproto.debugpb;
const metapb = kvproto.metapb;
const transport = @import("transport.zig");
const kv = @import("../kv/mod.zig");
const types = @import("types.zig");
const oracle = @import("../oracle/oracle.zig");

/// Aligns with Go's tikvrpc request kinds (subset, extend as needed)
pub const RequestType = enum {
    // Transactional
    Get,
    BatchGet,
    Prewrite,
    Commit,
    Cleanup,
    Scan,
    PessimisticLock,
    PessimisticRollback,
    CheckTxnStatus,
    CheckSecondaryLocks,
    TxnHeartBeat,
    ResolveLock,
    BatchRollback,
    ScanLock,
    GC,
    DeleteRange,

    // RawKV
    RawGet,
    RawBatchGet,
    RawPut,
    RawBatchPut,
    RawDelete,
    RawBatchDelete,
    RawDeleteRange,
    RawScan,
    GetKeyTTL,
    RawCompareAndSwap,

    // Admin/Unsafe
    UnsafeDestroyRange,

    // Lock observer / debug-like
    RegisterLockObserver,
    CheckLockObserver,
    RemoveLockObserver,
    PhysicalScanLock,
    StoreSafeTS,
    LockWaitInfo,

    // Coprocessor
    Coprocessor,
    CoprocessorStream,
    BatchCop,

    // MPP
    MPPTask,
    MPPConn,
    MPPCancel,
    MPPAlive,

    // MVCC / Split / Debug
    MvccGetByKey,
    MvccGetByStartTs,
    SplitRegion,
    DebugGetRegionProperties,

    // Empty
    Empty,

    // Fallback
    Unknown,
};

/// Request priority (maps to kvrpcpb.CommandPri in send path)
pub const Priority = enum { low, normal, high };

/// Replica read preference (maps to follower/leader preferences in Go client)
pub const ReplicaRead = enum { leader, follower, leader_and_follower };

/// Disk full behavior (subset)
pub const DiskFullOpt = enum { default, forbid, allow };

/// Options common across requests, mirroring Go client shape where practical
pub const RequestOptions = struct {
    priority: Priority = .normal,
    replica_read: ReplicaRead = .leader,
    not_fill_cache: bool = false,
    sync_log: bool = false,
    keep_order: bool = false,
    resource_group_tag: []const u8 = &[_]u8{},
    disk_full_opt: DiskFullOpt = .default,
    // ---- Moved from Request for ergonomics ----
    read_replica_scope: []const u8 = &.{},
    // remove txnScope after tidb removed txnScope (kept for compatibility)
    txn_scope: []const u8 = &.{},
    // Different from kvrpcpb.Context.ReplicaRead
    replica_read_type: kv.ReplicaReadType = .Leader,
    // pointer to follower read seed in snapshot/coprocessor
    replica_read_seed: ?*u32 = null,
    // Matches Go's Request.ReplicaRead and StaleRead helpers
    replica_read_flag: bool = false,
    stale_read: bool = false,
    store_tp: types.EndpointType = .TiKV,
    // forwarded host address if request is proxied by another store
    forwarded_host: []const u8 = &.{},
};

pub const Lease = struct { dummy: u8 = 0 };

pub const CopStreamResponse = struct {
    stream: ?*transport.StreamHandle = null,
    first: ?coprocessor.Response = null,
    timeout_ns: u64 = 0,
    lease: Lease = .{},
};

pub const BatchCopStreamResponse = struct {
    stream: ?*transport.StreamHandle = null,
    first: ?coprocessor.BatchResponse = null,
    timeout_ns: u64 = 0,
    lease: Lease = .{},
};

pub const MPPStreamResponse = struct {
    stream: ?*transport.StreamHandle = null,
    first: ?mpp.MPPDataPacket = null,
    timeout_ns: u64 = 0,
    lease: Lease = .{},
};

/// Union payload matching RequestType
pub const Payload = union(RequestType) {
    Get: kvrpcpb.GetRequest,
    BatchGet: kvrpcpb.BatchGetRequest,
    Prewrite: kvrpcpb.PrewriteRequest,
    Commit: kvrpcpb.CommitRequest,
    Cleanup: kvrpcpb.CleanupRequest,
    Scan: kvrpcpb.ScanRequest,
    PessimisticLock: kvrpcpb.PessimisticLockRequest,
    PessimisticRollback: kvrpcpb.PessimisticRollbackRequest,
    CheckTxnStatus: kvrpcpb.CheckTxnStatusRequest,
    CheckSecondaryLocks: kvrpcpb.CheckSecondaryLocksRequest,
    TxnHeartBeat: kvrpcpb.TxnHeartBeatRequest,
    ResolveLock: kvrpcpb.ResolveLockRequest,
    BatchRollback: kvrpcpb.BatchRollbackRequest,
    ScanLock: kvrpcpb.ScanLockRequest,
    GC: kvrpcpb.GCRequest,
    DeleteRange: kvrpcpb.DeleteRangeRequest,

    RawGet: kvrpcpb.RawGetRequest,
    RawBatchGet: kvrpcpb.RawBatchGetRequest,
    RawPut: kvrpcpb.RawPutRequest,
    RawBatchPut: kvrpcpb.RawBatchPutRequest,
    RawDelete: kvrpcpb.RawDeleteRequest,
    RawBatchDelete: kvrpcpb.RawBatchDeleteRequest,
    RawDeleteRange: kvrpcpb.RawDeleteRangeRequest,
    RawScan: kvrpcpb.RawScanRequest,
    GetKeyTTL: kvrpcpb.RawGetKeyTTLRequest,
    RawCompareAndSwap: kvrpcpb.RawCASRequest,

    UnsafeDestroyRange: kvrpcpb.UnsafeDestroyRangeRequest,

    RegisterLockObserver: kvrpcpb.RegisterLockObserverRequest,
    CheckLockObserver: kvrpcpb.CheckLockObserverRequest,
    RemoveLockObserver: kvrpcpb.RemoveLockObserverRequest,
    PhysicalScanLock: kvrpcpb.PhysicalScanLockRequest,
    StoreSafeTS: kvrpcpb.StoreSafeTSRequest,
    LockWaitInfo: kvrpcpb.GetLockWaitInfoRequest,

    Coprocessor: coprocessor.Request,
    CoprocessorStream: coprocessor.Request,
    BatchCop: coprocessor.BatchRequest,

    MPPTask: mpp.DispatchTaskRequest,
    MPPConn: mpp.EstablishMPPConnectionRequest,
    MPPCancel: mpp.CancelTaskRequest,
    MPPAlive: mpp.IsAliveRequest,

    MvccGetByKey: kvrpcpb.MvccGetByKeyRequest,
    MvccGetByStartTs: kvrpcpb.MvccGetByStartTsRequest,
    SplitRegion: kvrpcpb.SplitRegionRequest,
    DebugGetRegionProperties: debugpb.GetRegionPropertiesRequest,

    Empty: void,

    Unknown: void,
};

/// The primary request wrapper (Go's tikvrpc.Request analogue)
pub const Request = struct {
    typ: RequestType,
    payload: Payload,
    opts: RequestOptions = .{},

    // Additional metadata to mirror Go's tikvrpc.Request
    // Embedded context separate from proto payload context (optional)
    context: ?kvrpcpb.Context = null,

    pub fn fromGet(req: kvrpcpb.GetRequest, opts: RequestOptions) Request {
        return .{ .typ = .Get, .payload = .{ .Get = req }, .opts = opts };
    }

    // ---------------- Helper methods (parity with Go) ----------------

    pub fn getReplicaReadSeed(self: *const Request) ?*u32 {
        return self.opts.replica_read_seed;
    }

    pub fn enableStaleRead(self: *Request) void {
        self.opts.stale_read = true;
        self.opts.replica_read_type = .Mixed;
        self.opts.replica_read_flag = false;
    }

    pub fn getStaleRead(self: *const Request) bool {
        return self.opts.stale_read;
    }

    pub fn isGlobalStaleRead(self: *const Request) bool {
        return std.mem.eql(u8, self.opts.read_replica_scope, oracle.GLOBAL_TXN_SCOPE) and
            std.mem.eql(u8, self.opts.txn_scope, oracle.GLOBAL_TXN_SCOPE) and
            self.getStaleRead();
    }

    pub fn isDebugReq(self: *const Request) bool {
        return self.typ == .DebugGetRegionProperties;
    }

    pub fn isTxnWriteRequest(self: *const Request) bool {
        return switch (self.typ) {
            .PessimisticLock, .Prewrite, .Commit, .BatchRollback, .PessimisticRollback, .CheckTxnStatus, .CheckSecondaryLocks, .Cleanup, .TxnHeartBeat, .ResolveLock => true,
            else => false,
        };
    }
    pub fn fromBatchGet(req: kvrpcpb.BatchGetRequest, opts: RequestOptions) Request {
        return .{ .typ = .BatchGet, .payload = .{ .BatchGet = req }, .opts = opts };
    }
    pub fn fromPrewrite(req: kvrpcpb.PrewriteRequest, opts: RequestOptions) Request {
        return .{ .typ = .Prewrite, .payload = .{ .Prewrite = req }, .opts = opts };
    }
    pub fn fromCommit(req: kvrpcpb.CommitRequest, opts: RequestOptions) Request {
        return .{ .typ = .Commit, .payload = .{ .Commit = req }, .opts = opts };
    }
    pub fn fromCleanup(req: kvrpcpb.CleanupRequest, opts: RequestOptions) Request {
        return .{ .typ = .Cleanup, .payload = .{ .Cleanup = req }, .opts = opts };
    }
    pub fn fromScan(req: kvrpcpb.ScanRequest, opts: RequestOptions) Request {
        return .{ .typ = .Scan, .payload = .{ .Scan = req }, .opts = opts };
    }
    pub fn fromPessimisticLock(req: kvrpcpb.PessimisticLockRequest, opts: RequestOptions) Request {
        return .{ .typ = .PessimisticLock, .payload = .{ .PessimisticLock = req }, .opts = opts };
    }
    pub fn fromCheckTxnStatus(req: kvrpcpb.CheckTxnStatusRequest, opts: RequestOptions) Request {
        return .{ .typ = .CheckTxnStatus, .payload = .{ .CheckTxnStatus = req }, .opts = opts };
    }
    pub fn fromResolveLock(req: kvrpcpb.ResolveLockRequest, opts: RequestOptions) Request {
        return .{ .typ = .ResolveLock, .payload = .{ .ResolveLock = req }, .opts = opts };
    }
    pub fn fromPessimisticRollback(req: kvrpcpb.PessimisticRollbackRequest, opts: RequestOptions) Request {
        return .{ .typ = .PessimisticRollback, .payload = .{ .PessimisticRollback = req }, .opts = opts };
    }
    pub fn fromCheckSecondaryLocks(req: kvrpcpb.CheckSecondaryLocksRequest, opts: RequestOptions) Request {
        return .{ .typ = .CheckSecondaryLocks, .payload = .{ .CheckSecondaryLocks = req }, .opts = opts };
    }
    pub fn fromTxnHeartBeat(req: kvrpcpb.TxnHeartBeatRequest, opts: RequestOptions) Request {
        return .{ .typ = .TxnHeartBeat, .payload = .{ .TxnHeartBeat = req }, .opts = opts };
    }
    pub fn fromBatchRollback(req: kvrpcpb.BatchRollbackRequest, opts: RequestOptions) Request {
        return .{ .typ = .BatchRollback, .payload = .{ .BatchRollback = req }, .opts = opts };
    }
    pub fn fromScanLock(req: kvrpcpb.ScanLockRequest, opts: RequestOptions) Request {
        return .{ .typ = .ScanLock, .payload = .{ .ScanLock = req }, .opts = opts };
    }
    pub fn fromGC(req: kvrpcpb.GCRequest, opts: RequestOptions) Request {
        return .{ .typ = .GC, .payload = .{ .GC = req }, .opts = opts };
    }
    pub fn fromDeleteRange(req: kvrpcpb.DeleteRangeRequest, opts: RequestOptions) Request {
        return .{ .typ = .DeleteRange, .payload = .{ .DeleteRange = req }, .opts = opts };
    }

    pub fn fromRawGet(req: kvrpcpb.RawGetRequest, opts: RequestOptions) Request {
        return .{ .typ = .RawGet, .payload = .{ .RawGet = req }, .opts = opts };
    }
    pub fn fromRawBatchGet(req: kvrpcpb.RawBatchGetRequest, opts: RequestOptions) Request {
        return .{ .typ = .RawBatchGet, .payload = .{ .RawBatchGet = req }, .opts = opts };
    }
    pub fn fromRawPut(req: kvrpcpb.RawPutRequest, opts: RequestOptions) Request {
        return .{ .typ = .RawPut, .payload = .{ .RawPut = req }, .opts = opts };
    }
    pub fn fromRawBatchPut(req: kvrpcpb.RawBatchPutRequest, opts: RequestOptions) Request {
        return .{ .typ = .RawBatchPut, .payload = .{ .RawBatchPut = req }, .opts = opts };
    }
    pub fn fromRawDelete(req: kvrpcpb.RawDeleteRequest, opts: RequestOptions) Request {
        return .{ .typ = .RawDelete, .payload = .{ .RawDelete = req }, .opts = opts };
    }
    pub fn fromRawBatchDelete(req: kvrpcpb.RawBatchDeleteRequest, opts: RequestOptions) Request {
        return .{ .typ = .RawBatchDelete, .payload = .{ .RawBatchDelete = req }, .opts = opts };
    }
    pub fn fromRawDeleteRange(req: kvrpcpb.RawDeleteRangeRequest, opts: RequestOptions) Request {
        return .{ .typ = .RawDeleteRange, .payload = .{ .RawDeleteRange = req }, .opts = opts };
    }
    pub fn fromRawScan(req: kvrpcpb.RawScanRequest, opts: RequestOptions) Request {
        return .{ .typ = .RawScan, .payload = .{ .RawScan = req }, .opts = opts };
    }
    pub fn fromGetKeyTTL(req: kvrpcpb.RawGetKeyTTLRequest, opts: RequestOptions) Request {
        return .{ .typ = .GetKeyTTL, .payload = .{ .GetKeyTTL = req }, .opts = opts };
    }
    pub fn fromRawCompareAndSwap(req: kvrpcpb.RawCASRequest, opts: RequestOptions) Request {
        return .{ .typ = .RawCompareAndSwap, .payload = .{ .RawCompareAndSwap = req }, .opts = opts };
    }

    pub fn fromUnsafeDestroyRange(req: kvrpcpb.UnsafeDestroyRangeRequest, opts: RequestOptions) Request {
        return .{ .typ = .UnsafeDestroyRange, .payload = .{ .UnsafeDestroyRange = req }, .opts = opts };
    }

    pub fn fromRegisterLockObserver(req: kvrpcpb.RegisterLockObserverRequest, opts: RequestOptions) Request {
        return .{ .typ = .RegisterLockObserver, .payload = .{ .RegisterLockObserver = req }, .opts = opts };
    }
    pub fn fromCheckLockObserver(req: kvrpcpb.CheckLockObserverRequest, opts: RequestOptions) Request {
        return .{ .typ = .CheckLockObserver, .payload = .{ .CheckLockObserver = req }, .opts = opts };
    }
    pub fn fromRemoveLockObserver(req: kvrpcpb.RemoveLockObserverRequest, opts: RequestOptions) Request {
        return .{ .typ = .RemoveLockObserver, .payload = .{ .RemoveLockObserver = req }, .opts = opts };
    }
    pub fn fromPhysicalScanLock(req: kvrpcpb.PhysicalScanLockRequest, opts: RequestOptions) Request {
        return .{ .typ = .PhysicalScanLock, .payload = .{ .PhysicalScanLock = req }, .opts = opts };
    }
    pub fn fromStoreSafeTS(req: kvrpcpb.StoreSafeTSRequest, opts: RequestOptions) Request {
        return .{ .typ = .StoreSafeTS, .payload = .{ .StoreSafeTS = req }, .opts = opts };
    }
    pub fn fromLockWaitInfo(req: kvrpcpb.GetLockWaitInfoRequest, opts: RequestOptions) Request {
        return .{ .typ = .LockWaitInfo, .payload = .{ .LockWaitInfo = req }, .opts = opts };
    }

    pub fn fromCoprocessor(req: coprocessor.CoprocessorRequest, opts: RequestOptions) Request {
        return .{ .typ = .Coprocessor, .payload = .{ .Coprocessor = req }, .opts = opts };
    }
    pub fn fromCoprocessorStream(req: coprocessor.CoprocessorRequest, opts: RequestOptions) Request {
        return .{ .typ = .CoprocessorStream, .payload = .{ .CoprocessorStream = req }, .opts = opts };
    }
    pub fn fromBatchCop(req: coprocessor.BatchRequest, opts: RequestOptions) Request {
        return .{ .typ = .BatchCop, .payload = .{ .BatchCop = req }, .opts = opts };
    }

    pub fn fromMPPTask(req: mpp.DispatchTaskRequest, opts: RequestOptions) Request {
        return .{ .typ = .MPPTask, .payload = .{ .MPPTask = req }, .opts = opts };
    }
    pub fn fromMPPConn(req: mpp.EstablishMPPConnectionRequest, opts: RequestOptions) Request {
        return .{ .typ = .MPPConn, .payload = .{ .MPPConn = req }, .opts = opts };
    }
    pub fn fromMPPCancel(req: mpp.CancelTaskRequest, opts: RequestOptions) Request {
        return .{ .typ = .MPPCancel, .payload = .{ .MPPCancel = req }, .opts = opts };
    }
    pub fn fromMPPAlive(req: mpp.IsAliveRequest, opts: RequestOptions) Request {
        return .{ .typ = .MPPAlive, .payload = .{ .MPPAlive = req }, .opts = opts };
    }

    pub fn fromMvccGetByKey(req: kvrpcpb.MvccGetByKeyRequest, opts: RequestOptions) Request {
        return .{ .typ = .MvccGetByKey, .payload = .{ .MvccGetByKey = req }, .opts = opts };
    }
    pub fn fromMvccGetByStartTs(req: kvrpcpb.MvccGetByStartTsRequest, opts: RequestOptions) Request {
        return .{ .typ = .MvccGetByStartTs, .payload = .{ .MvccGetByStartTs = req }, .opts = opts };
    }
    pub fn fromSplitRegion(req: kvrpcpb.SplitRegionRequest, opts: RequestOptions) Request {
        return .{ .typ = .SplitRegion, .payload = .{ .SplitRegion = req }, .opts = opts };
    }
    pub fn fromDebugGetRegionProperties(req: debugpb.GetRegionPropertiesRequest, opts: RequestOptions) Request {
        return .{ .typ = .DebugGetRegionProperties, .payload = .{ .DebugGetRegionProperties = req }, .opts = opts };
    }

    pub fn fromEmpty() Request {
        return .{ .typ = .Empty, .payload = .{ .Empty = {} }, .opts = .{} };
    }

    pub fn unknown() Request {
        return .{ .typ = .Unknown, .payload = .{ .Unknown = {} }, .opts = .{} };
    }
};

/// Set the Request.context and propagate it into the inner proto payload, mirroring Go's SetContext.
pub fn setContext(req: *Request, region: ?*const metapb.Region, peer: ?*const metapb.Peer) void {
    if (req.context == null) req.context = .{};
    var ctx = &req.context.?;
    if (region) |r| {
        ctx.region_id = r.id;
        ctx.region_epoch = r.region_epoch;
    }
    ctx.peer = if (peer) |p| p.* else null;

    // Assign context to the inner message based on request type
    switch (req.payload) {
        .Get => |*m| m.context = req.context,
        .BatchGet => |*m| m.context = req.context,
        .Prewrite => |*m| m.context = req.context,
        .Commit => |*m| m.context = req.context,
        .Cleanup => |*m| m.context = req.context,
        .Scan => |*m| m.context = req.context,
        .PessimisticLock => |*m| m.context = req.context,
        .PessimisticRollback => |*m| m.context = req.context,
        .CheckTxnStatus => |*m| m.context = req.context,
        .CheckSecondaryLocks => |*m| m.context = req.context,
        .TxnHeartBeat => |*m| m.context = req.context,
        .ResolveLock => |*m| m.context = req.context,
        .BatchRollback => |*m| m.context = req.context,
        .ScanLock => |*m| m.context = req.context,
        .GC => |*m| m.context = req.context,
        .DeleteRange => |*m| m.context = req.context,
        .RawGet => |*m| m.context = req.context,
        .RawBatchGet => |*m| m.context = req.context,
        .RawPut => |*m| m.context = req.context,
        .RawBatchPut => |*m| m.context = req.context,
        .RawDelete => |*m| m.context = req.context,
        .RawBatchDelete => |*m| m.context = req.context,
        .RawDeleteRange => |*m| m.context = req.context,
        .RawScan => |*m| m.context = req.context,
        .GetKeyTTL => |*m| m.context = req.context,
        .RawCompareAndSwap => |*m| m.context = req.context,
        .UnsafeDestroyRange => |*m| m.context = req.context,
        .RegisterLockObserver => |*m| m.context = req.context,
        .CheckLockObserver => |*m| m.context = req.context,
        .RemoveLockObserver => |*m| m.context = req.context,
        .PhysicalScanLock => |*m| m.context = req.context,
        .Coprocessor => |*m| m.context = req.context,
        .CoprocessorStream => |*m| m.context = req.context,
        .BatchCop => |*m| m.context = req.context,
        .MPPTask => {}, // store-level
        .MPPConn => |*m| {
            _ = m; // connection is store-level
        },
        .MPPCancel => |*m| {
            _ = m;
        },
        .MPPAlive => |*m| {
            _ = m;
        },
        .MvccGetByKey => |*m| m.context = req.context,
        .MvccGetByStartTs => |*m| m.context = req.context,
        .SplitRegion => |*m| m.context = req.context,
        .DebugGetRegionProperties => |*m| {
            _ = m; // debugpb request does not carry kvrpcpb.Context
        },
        .Empty => {},
        .Unknown => {},
    }
}

test "tikvrpc Request builders compile" {
    const get_req: kvrpcpb.GetRequest = .{ .context = .{ .region_id = 0 }, .key = "k" };
    const r = Request.fromGet(get_req, .{ .priority = .high, .not_fill_cache = true });
    try std.testing.expect(r.typ == .Get);
    try std.testing.expect(r.opts.priority == .high);
}
