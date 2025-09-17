const std = @import("std");
const kvproto = @import("kvproto");
const kvrpcpb = kvproto.kvrpcpb;
const coprocessor = kvproto.coprocessor;

const request_mod = @import("request.zig");
const Request = request_mod.Request;

// Convenience accessors similar to Go's req.Get(), req.Scan(), etc.
// Mutable versions
pub fn asGet(r: *Request) ?*kvrpcpb.GetRequest {
    return if (r.payload == .Get) &r.payload.Get else null;
}
pub fn asScan(r: *Request) ?*kvrpcpb.ScanRequest {
    return if (r.payload == .Scan) &r.payload.Scan else null;
}
pub fn asPrewrite(r: *Request) ?*kvrpcpb.PrewriteRequest {
    return if (r.payload == .Prewrite) &r.payload.Prewrite else null;
}
pub fn asCommit(r: *Request) ?*kvrpcpb.CommitRequest {
    return if (r.payload == .Commit) &r.payload.Commit else null;
}
pub fn asCleanup(r: *Request) ?*kvrpcpb.CleanupRequest {
    return if (r.payload == .Cleanup) &r.payload.Cleanup else null;
}
pub fn asBatchGet(r: *Request) ?*kvrpcpb.BatchGetRequest {
    return if (r.payload == .BatchGet) &r.payload.BatchGet else null;
}
pub fn asBatchRollback(r: *Request) ?*kvrpcpb.BatchRollbackRequest {
    return if (r.payload == .BatchRollback) &r.payload.BatchRollback else null;
}
pub fn asScanLock(r: *Request) ?*kvrpcpb.ScanLockRequest {
    return if (r.payload == .ScanLock) &r.payload.ScanLock else null;
}
pub fn asResolveLock(r: *Request) ?*kvrpcpb.ResolveLockRequest {
    return if (r.payload == .ResolveLock) &r.payload.ResolveLock else null;
}
pub fn asPessimisticLock(r: *Request) ?*kvrpcpb.PessimisticLockRequest {
    return if (r.payload == .PessimisticLock) &r.payload.PessimisticLock else null;
}
pub fn asPessimisticRollback(r: *Request) ?*kvrpcpb.PessimisticRollbackRequest {
    return if (r.payload == .PessimisticRollback) &r.payload.PessimisticRollback else null;
}
pub fn asTxnHeartBeat(r: *Request) ?*kvrpcpb.TxnHeartBeatRequest {
    return if (r.payload == .TxnHeartBeat) &r.payload.TxnHeartBeat else null;
}
pub fn asCheckTxnStatus(r: *Request) ?*kvrpcpb.CheckTxnStatusRequest {
    return if (r.payload == .CheckTxnStatus) &r.payload.CheckTxnStatus else null;
}
pub fn asCheckSecondaryLocks(r: *Request) ?*kvrpcpb.CheckSecondaryLocksRequest {
    return if (r.payload == .CheckSecondaryLocks) &r.payload.CheckSecondaryLocks else null;
}

// RawKV
pub fn asRawGet(r: *Request) ?*kvrpcpb.RawGetRequest {
    return if (r.payload == .RawGet) &r.payload.RawGet else null;
}
pub fn asRawBatchGet(r: *Request) ?*kvrpcpb.RawBatchGetRequest {
    return if (r.payload == .RawBatchGet) &r.payload.RawBatchGet else null;
}
pub fn asRawPut(r: *Request) ?*kvrpcpb.RawPutRequest {
    return if (r.payload == .RawPut) &r.payload.RawPut else null;
}
pub fn asRawBatchPut(r: *Request) ?*kvrpcpb.RawBatchPutRequest {
    return if (r.payload == .RawBatchPut) &r.payload.RawBatchPut else null;
}
pub fn asRawDelete(r: *Request) ?*kvrpcpb.RawDeleteRequest {
    return if (r.payload == .RawDelete) &r.payload.RawDelete else null;
}
pub fn asRawBatchDelete(r: *Request) ?*kvrpcpb.RawBatchDeleteRequest {
    return if (r.payload == .RawBatchDelete) &r.payload.RawBatchDelete else null;
}
pub fn asRawDeleteRange(r: *Request) ?*kvrpcpb.RawDeleteRangeRequest {
    return if (r.payload == .RawDeleteRange) &r.payload.RawDeleteRange else null;
}
pub fn asRawScan(r: *Request) ?*kvrpcpb.RawScanRequest {
    return if (r.payload == .RawScan) &r.payload.RawScan else null;
}
pub fn asRawCoprocessor(r: *Request) ?*kvrpcpb.RawCoprocessorRequest {
    return if (r.payload == .RawCoprocessor) &r.payload.RawCoprocessor else null;
}
pub fn asReadIndex(r: *Request) ?*kvrpcpb.ReadIndexRequest {
    return if (r.payload == .ReadIndex) &r.payload.ReadIndex else null;
}

pub fn asReadIndexConst(r: *const Request) ?*const kvrpcpb.ReadIndexRequest {
    return if (r.payload == .ReadIndex) &r.payload.ReadIndex else null;
}

pub fn asRawCoprocessorConst(r: *const Request) ?*const kvrpcpb.RawCoprocessorRequest {
    return if (r.payload == .RawCoprocessor) &r.payload.RawCoprocessor else null;
}

// Coprocessor: both Coprocessor and CoprocessorStream carry coprocessor.Request
pub fn asCop(r: *Request) ?*coprocessor.Request {
    return switch (r.payload) {
        .Coprocessor => &r.payload.Coprocessor,
        .CoprocessorStream => &r.payload.CoprocessorStream,
        else => null,
    };
}

// Const versions
pub fn asGetConst(r: *const Request) ?*const kvrpcpb.GetRequest {
    return if (r.payload == .Get) &r.payload.Get else null;
}
pub fn asScanConst(r: *const Request) ?*const kvrpcpb.ScanRequest {
    return if (r.payload == .Scan) &r.payload.Scan else null;
}
pub fn asPrewriteConst(r: *const Request) ?*const kvrpcpb.PrewriteRequest {
    return if (r.payload == .Prewrite) &r.payload.Prewrite else null;
}
pub fn asCommitConst(r: *const Request) ?*const kvrpcpb.CommitRequest {
    return if (r.payload == .Commit) &r.payload.Commit else null;
}
pub fn asCleanupConst(r: *const Request) ?*const kvrpcpb.CleanupRequest {
    return if (r.payload == .Cleanup) &r.payload.Cleanup else null;
}
pub fn asBatchGetConst(r: *const Request) ?*const kvrpcpb.BatchGetRequest {
    return if (r.payload == .BatchGet) &r.payload.BatchGet else null;
}
pub fn asBatchRollbackConst(r: *const Request) ?*const kvrpcpb.BatchRollbackRequest {
    return if (r.payload == .BatchRollback) &r.payload.BatchRollback else null;
}
pub fn asScanLockConst(r: *const Request) ?*const kvrpcpb.ScanLockRequest {
    return if (r.payload == .ScanLock) &r.payload.ScanLock else null;
}
pub fn asResolveLockConst(r: *const Request) ?*const kvrpcpb.ResolveLockRequest {
    return if (r.payload == .ResolveLock) &r.payload.ResolveLock else null;
}
pub fn asPessimisticLockConst(r: *const Request) ?*const kvrpcpb.PessimisticLockRequest {
    return if (r.payload == .PessimisticLock) &r.payload.PessimisticLock else null;
}
pub fn asPessimisticRollbackConst(r: *const Request) ?*const kvrpcpb.PessimisticRollbackRequest {
    return if (r.payload == .PessimisticRollback) &r.payload.PessimisticRollback else null;
}
pub fn asTxnHeartBeatConst(r: *const Request) ?*const kvrpcpb.TxnHeartBeatRequest {
    return if (r.payload == .TxnHeartBeat) &r.payload.TxnHeartBeat else null;
}
pub fn asCheckTxnStatusConst(r: *const Request) ?*const kvrpcpb.CheckTxnStatusRequest {
    return if (r.payload == .CheckTxnStatus) &r.payload.CheckTxnStatus else null;
}
pub fn asCheckSecondaryLocksConst(r: *const Request) ?*const kvrpcpb.CheckSecondaryLocksRequest {
    return if (r.payload == .CheckSecondaryLocks) &r.payload.CheckSecondaryLocks else null;
}

pub fn asRawGetConst(r: *const Request) ?*const kvrpcpb.RawGetRequest {
    return if (r.payload == .RawGet) &r.payload.RawGet else null;
}
pub fn asRawBatchGetConst(r: *const Request) ?*const kvrpcpb.RawBatchGetRequest {
    return if (r.payload == .RawBatchGet) &r.payload.RawBatchGet else null;
}
pub fn asRawPutConst(r: *const Request) ?*const kvrpcpb.RawPutRequest {
    return if (r.payload == .RawPut) &r.payload.RawPut else null;
}
pub fn asRawBatchPutConst(r: *const Request) ?*const kvrpcpb.RawBatchPutRequest {
    return if (r.payload == .RawBatchPut) &r.payload.RawBatchPut else null;
}
pub fn asRawDeleteConst(r: *const Request) ?*const kvrpcpb.RawDeleteRequest {
    return if (r.payload == .RawDelete) &r.payload.RawDelete else null;
}
pub fn asRawBatchDeleteConst(r: *const Request) ?*const kvrpcpb.RawBatchDeleteRequest {
    return if (r.payload == .RawBatchDelete) &r.payload.RawBatchDelete else null;
}
pub fn asRawDeleteRangeConst(r: *const Request) ?*const kvrpcpb.RawDeleteRangeRequest {
    return if (r.payload == .RawDeleteRange) &r.payload.RawDeleteRange else null;
}
pub fn asRawScanConst(r: *const Request) ?*const kvrpcpb.RawScanRequest {
    return if (r.payload == .RawScan) &r.payload.RawScan else null;
}

pub fn asCopConst(r: *const Request) ?*const coprocessor.Request {
    return switch (r.payload) {
        .Coprocessor => &r.payload.Coprocessor,
        .CoprocessorStream => &r.payload.CoprocessorStream,
        else => null,
    };
}
