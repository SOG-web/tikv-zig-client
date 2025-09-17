const std = @import("std");
const kvproto = @import("kvproto");
const kvrpcpb = kvproto.kvrpcpb;
const tikvpb = kvproto.tikvpb;
const coprocessor = kvproto.coprocessor;
const request_mod = @import("request.zig");

pub const Request = request_mod.Request;
pub const RequestType = request_mod.RequestType;

// A typed wrapper similar to Go's `Response{ Resp interface{} }`
// but with compile-time safety via a tagged union.
pub const Response = struct {
    payload: Payload,

    pub const Payload = union(enum) {
        Get: kvrpcpb.GetResponse,
        Scan: kvrpcpb.ScanResponse,
        Prewrite: kvrpcpb.PrewriteResponse,
        Commit: kvrpcpb.CommitResponse,
        Import: kvrpcpb.ImportResponse,
        Cleanup: kvrpcpb.CleanupResponse,
        BatchGet: kvrpcpb.BatchGetResponse,
        BatchRollback: kvrpcpb.BatchRollbackResponse,
        ScanLock: kvrpcpb.ScanLockResponse,
        ResolveLock: kvrpcpb.ResolveLockResponse,
        GC: kvrpcpb.GCResponse,
        DeleteRange: kvrpcpb.DeleteRangeResponse,
        RawGet: kvrpcpb.RawGetResponse,
        RawBatchGet: kvrpcpb.RawBatchGetResponse,
        RawPut: kvrpcpb.RawPutResponse,
        RawBatchPut: kvrpcpb.RawBatchPutResponse,
        RawDelete: kvrpcpb.RawDeleteResponse,
        RawBatchDelete: kvrpcpb.RawBatchDeleteResponse,
        RawScan: kvrpcpb.RawScanResponse,
        RawDeleteRange: kvrpcpb.RawDeleteRangeResponse,
        RawBatchScan: kvrpcpb.RawBatchScanResponse,
        ReadIndex: kvrpcpb.ReadIndexResponse,
        Coprocessor: coprocessor.Response,
        PessimisticLock: kvrpcpb.PessimisticLockResponse,
        PessimisticRollback: kvrpcpb.PessimisticRollbackResponse,
        CheckTxnStatus: kvrpcpb.CheckTxnStatusResponse,
        TxnHeartBeat: kvrpcpb.TxnHeartBeatResponse,
        CheckSecondaryLocks: kvrpcpb.CheckSecondaryLocksResponse,
        RawCoprocessor: kvrpcpb.RawCoprocessorResponse,
        FlashbackToVersion: kvrpcpb.FlashbackToVersionResponse,
        PrepareFlashbackToVersion: kvrpcpb.PrepareFlashbackToVersionResponse,
        Empty: tikvpb.BatchCommandsEmptyResponse,
    };
};

pub const CodecError = error{ Unsupported, UnknownCommand };

// Convert a single tikvrpc Request into tikvpb.BatchCommandsRequest.Request (oneof).
pub fn toBatchCommandsRequest(req: *const Request) CodecError!tikvpb.BatchCommandsRequest.Request {
    var out: tikvpb.BatchCommandsRequest.Request = .{};
    switch (req.payload) {
        .Get => |m| out.cmd = .{ .Get = m },
        .Scan => |m| out.cmd = .{ .Scan = m },
        .Prewrite => |m| out.cmd = .{ .Prewrite = m },
        .Commit => |m| out.cmd = .{ .Commit = m },
        .Cleanup => |m| out.cmd = .{ .Cleanup = m },
        .BatchGet => |m| out.cmd = .{ .BatchGet = m },
        .BatchRollback => |m| out.cmd = .{ .BatchRollback = m },
        .ScanLock => |m| out.cmd = .{ .ScanLock = m },
        .ResolveLock => |m| out.cmd = .{ .ResolveLock = m },
        .GC => |m| out.cmd = .{ .GC = m },
        .DeleteRange => |m| out.cmd = .{ .DeleteRange = m },
        .RawGet => |m| out.cmd = .{ .RawGet = m },
        .RawBatchGet => |m| out.cmd = .{ .RawBatchGet = m },
        .RawPut => |m| out.cmd = .{ .RawPut = m },
        .RawBatchPut => |m| out.cmd = .{ .RawBatchPut = m },
        .RawDelete => |m| out.cmd = .{ .RawDelete = m },
        .RawBatchDelete => |m| out.cmd = .{ .RawBatchDelete = m },
        .RawDeleteRange => |m| out.cmd = .{ .RawDeleteRange = m },
        .RawScan => |m| out.cmd = .{ .RawScan = m },
        .Coprocessor => |m| out.cmd = .{ .Coprocessor = m },
        .PessimisticLock => |m| out.cmd = .{ .PessimisticLock = m },
        .PessimisticRollback => |m| out.cmd = .{ .PessimisticRollback = m },
        .CheckTxnStatus => |m| out.cmd = .{ .CheckTxnStatus = m },
        .TxnHeartBeat => |m| out.cmd = .{ .TxnHeartBeat = m },
        .CheckSecondaryLocks => |m| out.cmd = .{ .CheckSecondaryLocks = m },
        .ReadIndex => |m| out.cmd = .{ .ReadIndex = m },
        .Empty => |_| out.cmd = .{ .Empty = .{} },
        // Unsupported in batch commands path
        .CoprocessorStream, .BatchCop, .MPPTask, .MPPConn, .MPPCancel, .MPPAlive, .MvccGetByKey, .MvccGetByStartTs, .SplitRegion, .DebugGetRegionProperties, .UnsafeDestroyRange, .GetKeyTTL, .RawCompareAndSwap => return CodecError.Unsupported,
        .Unknown => return CodecError.UnknownCommand,
    }
    return out;
}

// Package an array of Requests into a BatchCommandsRequest.
// request_ids will be filled sequentially starting from base_id (usually 0) unless provided separately later.
pub fn toBatchCommandsRequests(allocator: std.mem.Allocator, reqs: []const Request) CodecError!tikvpb.BatchCommandsRequest {
    var out: tikvpb.BatchCommandsRequest = .{};
    try out.requests.ensureTotalCapacity(allocator, reqs.len);
    try out.request_ids.ensureTotalCapacity(allocator, reqs.len);
    var i: usize = 0;
    while (i < reqs.len) : (i += 1) {
        const one = try toBatchCommandsRequest(&reqs[i]);
        try out.requests.append(allocator, one);
        try out.request_ids.append(allocator, @as(u64, @intCast(i))); // caller may overwrite with real ids
    }
    return out;
}

// Convert tikvpb.BatchCommandsResponse.Response into our typed Response wrapper.
pub fn fromBatchCommandsResponse(res: *const tikvpb.BatchCommandsResponse.Response) CodecError!Response {
    if (res.cmd == null) return CodecError.UnknownCommand;
    const c = &res.cmd.?;
    return Response{
        .payload = switch (c.*) {
            .Get => |m| .{ .Get = m },
            .Scan => |m| .{ .Scan = m },
            .Prewrite => |m| .{ .Prewrite = m },
            .Commit => |m| .{ .Commit = m },
            .Import => |m| .{ .Import = m },
            .Cleanup => |m| .{ .Cleanup = m },
            .BatchGet => |m| .{ .BatchGet = m },
            .BatchRollback => |m| .{ .BatchRollback = m },
            .ScanLock => |m| .{ .ScanLock = m },
            .ResolveLock => |m| .{ .ResolveLock = m },
            .GC => |m| .{ .GC = m },
            .DeleteRange => |m| .{ .DeleteRange = m },
            .RawGet => |m| .{ .RawGet = m },
            .RawBatchGet => |m| .{ .RawBatchGet = m },
            .RawPut => |m| .{ .RawPut = m },
            .RawBatchPut => |m| .{ .RawBatchPut = m },
            .RawDelete => |m| .{ .RawDelete = m },
            .RawBatchDelete => |m| .{ .RawBatchDelete = m },
            .RawScan => |m| .{ .RawScan = m },
            .RawDeleteRange => |m| .{ .RawDeleteRange = m },
            .RawBatchScan => |m| .{ .RawBatchScan = m },
            .Coprocessor => |m| .{ .Coprocessor = m },
            .PessimisticLock => |m| .{ .PessimisticLock = m },
            .PessimisticRollback => |m| .{ .PessimisticRollback = m },
            .CheckTxnStatus => |m| .{ .CheckTxnStatus = m },
            .TxnHeartBeat => |m| .{ .TxnHeartBeat = m },
            .CheckSecondaryLocks => |m| .{ .CheckSecondaryLocks = m },
            .RawCoprocessor => |m| .{ .RawCoprocessor = m },
            .FlashbackToVersion => |m| .{ .FlashbackToVersion = m },
            .PrepareFlashbackToVersion => |m| .{ .PrepareFlashbackToVersion = m },
            .ReadIndex => |m| .{ .ReadIndex = m },
            .Empty => |m| .{ .Empty = m },
        },
    };
}
