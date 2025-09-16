// TikvRPC Request/Response (Full Protobuf - Option B)
// This file defines Request/Response types using full protobuf messages,
// matching the Go client-go/tikvrpc approach exactly.
const std = @import("std");
const endpoint = @import("endpoint.zig");
const tikvrpc = @import("tikvrpc.zig");
const c = @import("../c.zig").c;

pub const CmdType = tikvrpc.CmdType;

// Helper function to convert Zig string to upb_StringView
fn sv(s: []const u8) c.upb_StringView {
    return c.upb_StringView{ .data = s.ptr, .size = s.len };
}

// Helper function to compare upb_StringView with Zig bytes
fn svEqBytes(sv_val: c.upb_StringView, bytes: []const u8) bool {
    if (sv_val.size != bytes.len) return false;
    return std.mem.eql(u8, sv_val.data[0..sv_val.size], bytes);
}

// ---- Full Protobuf Message Types ----
const UpbArena = [*c]c.upb_Arena;

// Request payload union using full protobuf message pointers
pub const RequestPayload = union(CmdType) {
    // Transactional KV operations (1-16)
    CmdGet: *c.kvrpcpb_GetRequest,
    CmdScan: *c.kvrpcpb_ScanRequest,
    CmdPrewrite: *c.kvrpcpb_PrewriteRequest,
    CmdCommit: *c.kvrpcpb_CommitRequest,
    CmdCleanup: *c.kvrpcpb_CleanupRequest,
    CmdBatchGet: *c.kvrpcpb_BatchGetRequest,
    CmdBatchRollback: *c.kvrpcpb_BatchRollbackRequest,
    CmdScanLock: *c.kvrpcpb_ScanLockRequest,
    CmdResolveLock: *c.kvrpcpb_ResolveLockRequest,
    CmdGC: *c.kvrpcpb_GCRequest,
    CmdDeleteRange: *c.kvrpcpb_DeleteRangeRequest,
    CmdPessimisticLock: *c.kvrpcpb_PessimisticLockRequest,
    CmdPessimisticRollback: *c.kvrpcpb_PessimisticRollbackRequest,
    CmdTxnHeartBeat: *c.kvrpcpb_TxnHeartBeatRequest,
    CmdCheckTxnStatus: *c.kvrpcpb_CheckTxnStatusRequest,
    CmdCheckSecondaryLocks: *c.kvrpcpb_CheckSecondaryLocksRequest,

    // RawKV operations (256-265)
    CmdRawGet: *c.kvrpcpb_RawGetRequest,
    CmdRawBatchGet: *c.kvrpcpb_RawBatchGetRequest,
    CmdRawPut: *c.kvrpcpb_RawPutRequest,
    CmdRawBatchPut: *c.kvrpcpb_RawBatchPutRequest,
    CmdRawDelete: *c.kvrpcpb_RawDeleteRequest,
    CmdRawBatchDelete: *c.kvrpcpb_RawBatchDeleteRequest,
    CmdRawDeleteRange: *c.kvrpcpb_RawDeleteRangeRequest,
    CmdRawScan: *c.kvrpcpb_RawScanRequest,
    CmdGetKeyTTL: *c.kvrpcpb_RawGetKeyTTLRequest,
    CmdRawCompareAndSwap: *c.kvrpcpb_RawCASRequest,

    // Other operations (266-272)
    CmdUnsafeDestroyRange: *c.kvrpcpb_UnsafeDestroyRangeRequest,
    CmdRegisterLockObserver: *anyopaque, // Placeholder
    CmdCheckLockObserver: *anyopaque, // Placeholder
    CmdRemoveLockObserver: *anyopaque, // Placeholder
    CmdPhysicalScanLock: *anyopaque, // Placeholder
    CmdStoreSafeTS: *c.kvrpcpb_StoreSafeTSRequest,
    CmdLockWaitInfo: *c.kvrpcpb_GetLockWaitInfoRequest,

    // Coprocessor operations (512+)
    CmdCop: *c.coprocessor_Request,
    CmdCopStream: *c.coprocessor_Request,
    CmdBatchCop: *c.coprocessor_BatchRequest,
    CmdMPPTask: *c.mpp_DispatchTaskRequest,
    CmdMPPConn: *c.mpp_EstablishMPPConnectionRequest,
    CmdMPPCancel: *c.mpp_CancelTaskRequest,
    CmdMPPAlive: *c.mpp_IsAliveRequest,

    // MVCC/Split operations (1024+)
    CmdMvccGetByKey: *c.debugpb_GetRequest,
    CmdMvccGetByStartTs: *c.debugpb_ScanMvccRequest,
    CmdSplitRegion: *c.debugpb_RegionInfoRequest,

    // Debug operations (2048+)
    CmdDebugGetRegionProperties: *c.debugpb_GetRegionPropertiesRequest,

    // Misc operations (3072+)
    CmdEmpty: *c.tikvpb_BatchCommandsEmptyRequest,
};

// Response payload union using full protobuf message pointers
pub const ResponsePayload = union(CmdType) {
    // Transactional KV responses (1-16)
    CmdGet: *c.kvrpcpb_GetResponse,
    CmdScan: *c.kvrpcpb_ScanResponse,
    CmdPrewrite: *c.kvrpcpb_PrewriteResponse,
    CmdCommit: *c.kvrpcpb_CommitResponse,
    CmdCleanup: *c.kvrpcpb_CleanupResponse,
    CmdBatchGet: *c.kvrpcpb_BatchGetResponse,
    CmdBatchRollback: *c.kvrpcpb_BatchRollbackResponse,
    CmdScanLock: *c.kvrpcpb_ScanLockResponse,
    CmdResolveLock: *c.kvrpcpb_ResolveLockResponse,
    CmdGC: *c.kvrpcpb_GCResponse,
    CmdDeleteRange: *c.kvrpcpb_DeleteRangeResponse,
    CmdPessimisticLock: *c.kvrpcpb_PessimisticLockResponse,
    CmdPessimisticRollback: *c.kvrpcpb_PessimisticRollbackResponse,
    CmdTxnHeartBeat: *c.kvrpcpb_TxnHeartBeatResponse,
    CmdCheckTxnStatus: *c.kvrpcpb_CheckTxnStatusResponse,
    CmdCheckSecondaryLocks: *c.kvrpcpb_CheckSecondaryLocksResponse,

    // RawKV responses (256-265)
    CmdRawGet: *c.kvrpcpb_RawGetResponse,
    CmdRawBatchGet: *c.kvrpcpb_RawBatchGetResponse,
    CmdRawPut: *c.kvrpcpb_RawPutResponse,
    CmdRawBatchPut: *c.kvrpcpb_RawBatchPutResponse,
    CmdRawDelete: *c.kvrpcpb_RawDeleteResponse,
    CmdRawBatchDelete: *c.kvrpcpb_RawBatchDeleteResponse,
    CmdRawDeleteRange: *c.kvrpcpb_RawDeleteRangeResponse,
    CmdRawScan: *c.kvrpcpb_RawScanResponse,
    CmdGetKeyTTL: *c.kvrpcpb_RawGetKeyTTLResponse,
    CmdRawCompareAndSwap: *c.kvrpcpb_RawCASResponse,

    // Other responses (266-272)
    CmdUnsafeDestroyRange: *c.kvrpcpb_UnsafeDestroyRangeResponse,
    CmdRegisterLockObserver: *anyopaque, // Placeholder
    CmdCheckLockObserver: *anyopaque, // Placeholder
    CmdRemoveLockObserver: *anyopaque, // Placeholder
    CmdPhysicalScanLock: *anyopaque, // Placeholder
    CmdStoreSafeTS: *c.kvrpcpb_StoreSafeTSResponse,
    CmdLockWaitInfo: *c.kvrpcpb_GetLockWaitInfoResponse,

    // Coprocessor responses (512+)
    CmdCop: *c.coprocessor_Response,
    CmdCopStream: *c.coprocessor_Response,
    CmdBatchCop: *c.coprocessor_BatchResponse,
    CmdMPPTask: *c.mpp_DispatchTaskResponse,
    CmdMPPConn: *c.mpp_MPPDataPacket,
    CmdMPPCancel: *c.mpp_CancelTaskResponse,
    CmdMPPAlive: *c.mpp_IsAliveResponse,

    // MVCC/Split responses (1024+)
    CmdMvccGetByKey: *c.debugpb_GetResponse,
    CmdMvccGetByStartTs: *c.debugpb_ScanMvccResponse,
    CmdSplitRegion: *c.debugpb_RegionInfoResponse,

    // Debug responses (2048+)
    CmdDebugGetRegionProperties: *c.debugpb_GetRegionPropertiesResponse,

    // Misc responses (3072+)
    CmdEmpty: *c.tikvpb_BatchCommandsEmptyResponse,
};

// Request struct matching Go tikvrpc.Request exactly
pub const Request = struct {
    typ: CmdType,
    req: RequestPayload,
    arena: UpbArena,
    context: *c.kvrpcpb_Context,
    read_replica_scope: []const u8 = "",
    txn_scope: []const u8 = "global",
    store_tp: endpoint.EndpointType = .TiKV,
    forwarded_host: []const u8 = "",

    // Constructor functions using full protobuf messages
    pub fn newRawGet(arena: UpbArena, key: []const u8, cf: []const u8) !Request {
        const req_msg = c.kvrpcpb_RawGetRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_RawGetRequest_set_key(req_msg, sv(key));
        c.kvrpcpb_RawGetRequest_set_cf(req_msg, sv(cf));
        c.kvrpcpb_RawGetRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdRawGet,
            .req = .{ .CmdRawGet = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newRawPut(arena: UpbArena, key: []const u8, value: []const u8, cf: []const u8) !Request {
        const req_msg = c.kvrpcpb_RawPutRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_RawPutRequest_set_key(req_msg, sv(key));
        c.kvrpcpb_RawPutRequest_set_value(req_msg, sv(value));
        c.kvrpcpb_RawPutRequest_set_cf(req_msg, sv(cf));
        c.kvrpcpb_RawPutRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdRawPut,
            .req = .{ .CmdRawPut = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newRawDelete(arena: UpbArena, key: []const u8, cf: []const u8) !Request {
        const req_msg = c.kvrpcpb_RawDeleteRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_RawDeleteRequest_set_key(req_msg, sv(key));
        c.kvrpcpb_RawDeleteRequest_set_cf(req_msg, sv(cf));
        c.kvrpcpb_RawDeleteRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdRawDelete,
            .req = .{ .CmdRawDelete = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newRawScan(arena: UpbArena, start_key: []const u8, end_key: []const u8, limit: u32, key_only: bool, cf: []const u8) !Request {
        const req_msg = c.kvrpcpb_RawScanRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_RawScanRequest_set_start_key(req_msg, sv(start_key));
        c.kvrpcpb_RawScanRequest_set_end_key(req_msg, sv(end_key));
        c.kvrpcpb_RawScanRequest_set_limit(req_msg, limit);
        c.kvrpcpb_RawScanRequest_set_key_only(req_msg, key_only);
        c.kvrpcpb_RawScanRequest_set_cf(req_msg, sv(cf));
        c.kvrpcpb_RawScanRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdRawScan,
            .req = .{ .CmdRawScan = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newRawBatchGet(arena: UpbArena, keys: [][]const u8, cf: []const u8) !Request {
        const req_msg = c.kvrpcpb_RawBatchGetRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_RawBatchGetRequest_set_cf(req_msg, sv(cf));

        // Set keys array
        const keys_array = c.kvrpcpb_RawBatchGetRequest_resize_keys(req_msg, keys.len, arena) orelse return error.OutOfMemory;
        for (keys, 0..) |key, i| {
            keys_array[i] = sv(key);
        }

        c.kvrpcpb_RawBatchGetRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdRawBatchGet,
            .req = .{ .CmdRawBatchGet = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newRawBatchPut(arena: UpbArena, keys: [][]const u8, values: [][]const u8, cf: []const u8) !Request {
        if (keys.len != values.len) return error.InvalidArgument;

        const req_msg = c.kvrpcpb_RawBatchPutRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_RawBatchPutRequest_set_cf(req_msg, sv(cf));

        // Set pairs array
        const pairs_array = c.kvrpcpb_RawBatchPutRequest_resize_pairs(req_msg, keys.len, arena) orelse return error.OutOfMemory;
        for (keys, values, 0..) |key, value, i| {
            const pair = pairs_array[i];
            c.kvrpcpb_KvPair_set_key(pair, sv(key));
            c.kvrpcpb_KvPair_set_value(pair, sv(value));
        }

        c.kvrpcpb_RawBatchPutRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdRawBatchPut,
            .req = .{ .CmdRawBatchPut = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newRawBatchDelete(arena: UpbArena, keys: [][]const u8, cf: []const u8) !Request {
        const req_msg = c.kvrpcpb_RawBatchDeleteRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_RawBatchDeleteRequest_set_cf(req_msg, sv(cf));

        // Set keys array
        const keys_array = c.kvrpcpb_RawBatchDeleteRequest_resize_keys(req_msg, keys.len, arena) orelse return error.OutOfMemory;
        for (keys, 0..) |key, i| {
            keys_array[i] = sv(key);
        }

        c.kvrpcpb_RawBatchDeleteRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdRawBatchDelete,
            .req = .{ .CmdRawBatchDelete = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newRawDeleteRange(arena: UpbArena, start_key: []const u8, end_key: []const u8, cf: []const u8) !Request {
        const req_msg = c.kvrpcpb_RawDeleteRangeRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_RawDeleteRangeRequest_set_start_key(req_msg, sv(start_key));
        c.kvrpcpb_RawDeleteRangeRequest_set_end_key(req_msg, sv(end_key));
        c.kvrpcpb_RawDeleteRangeRequest_set_cf(req_msg, sv(cf));
        c.kvrpcpb_RawDeleteRangeRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdRawDeleteRange,
            .req = .{ .CmdRawDeleteRange = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    // Transactional constructor functions
    pub fn newGet(arena: UpbArena, key: []const u8, version: u64) !Request {
        const req_msg = c.kvrpcpb_GetRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_GetRequest_set_key(req_msg, sv(key));
        c.kvrpcpb_GetRequest_set_version(req_msg, version);
        c.kvrpcpb_GetRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdGet,
            .req = .{ .CmdGet = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newScan(arena: UpbArena, start_key: []const u8, end_key: []const u8, limit: u32, version: u64) !Request {
        const req_msg = c.kvrpcpb_ScanRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_ScanRequest_set_start_key(req_msg, sv(start_key));
        c.kvrpcpb_ScanRequest_set_end_key(req_msg, sv(end_key));
        c.kvrpcpb_ScanRequest_set_limit(req_msg, limit);
        c.kvrpcpb_ScanRequest_set_version(req_msg, version);
        c.kvrpcpb_ScanRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdScan,
            .req = .{ .CmdScan = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newPrewrite(arena: UpbArena, mutations: []const u8, primary_lock: []const u8, start_ts: u64, lock_ttl: u64) !Request {
        const req_msg = c.kvrpcpb_PrewriteRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_PrewriteRequest_set_primary_lock(req_msg, sv(primary_lock));
        c.kvrpcpb_PrewriteRequest_set_start_version(req_msg, start_ts);
        c.kvrpcpb_PrewriteRequest_set_lock_ttl(req_msg, lock_ttl);
        c.kvrpcpb_PrewriteRequest_set_context(req_msg, ctx_msg);
        // TODO: Set mutations array
        _ = mutations;
        return .{
            .typ = .CmdPrewrite,
            .req = .{ .CmdPrewrite = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newCommit(arena: UpbArena, keys: [][]const u8, start_ts: u64, commit_ts: u64) !Request {
        const req_msg = c.kvrpcpb_CommitRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_CommitRequest_set_start_version(req_msg, start_ts);
        c.kvrpcpb_CommitRequest_set_commit_version(req_msg, commit_ts);

        // Set keys array
        const keys_array = c.kvrpcpb_CommitRequest_resize_keys(req_msg, keys.len, arena) orelse return error.OutOfMemory;
        for (keys, 0..) |key, i| {
            keys_array[i] = sv(key);
        }

        c.kvrpcpb_CommitRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdCommit,
            .req = .{ .CmdCommit = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newBatchGet(arena: UpbArena, keys: [][]const u8, version: u64) !Request {
        const req_msg = c.kvrpcpb_BatchGetRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_BatchGetRequest_set_version(req_msg, version);

        // Set keys array
        const keys_array = c.kvrpcpb_BatchGetRequest_resize_keys(req_msg, keys.len, arena) orelse return error.OutOfMemory;
        for (keys, 0..) |key, i| {
            keys_array[i] = sv(key);
        }

        c.kvrpcpb_BatchGetRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdBatchGet,
            .req = .{ .CmdBatchGet = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newPessimisticLock(arena: UpbArena, mutations: []const u8, primary_lock: []const u8, start_ts: u64, for_update_ts: u64, lock_ttl: u64) !Request {
        const req_msg = c.kvrpcpb_PessimisticLockRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_PessimisticLockRequest_set_primary_lock(req_msg, sv(primary_lock));
        c.kvrpcpb_PessimisticLockRequest_set_start_version(req_msg, start_ts);
        c.kvrpcpb_PessimisticLockRequest_set_for_update_ts(req_msg, for_update_ts);
        c.kvrpcpb_PessimisticLockRequest_set_lock_ttl(req_msg, lock_ttl);
        c.kvrpcpb_PessimisticLockRequest_set_context(req_msg, ctx_msg);
        // TODO: Set mutations array
        _ = mutations;
        return .{
            .typ = .CmdPessimisticLock,
            .req = .{ .CmdPessimisticLock = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newCleanup(arena: UpbArena, key: []const u8, start_ts: u64, current_ts: u64) !Request {
        const req_msg = c.kvrpcpb_CleanupRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_CleanupRequest_set_key(req_msg, sv(key));
        c.kvrpcpb_CleanupRequest_set_start_version(req_msg, start_ts);
        c.kvrpcpb_CleanupRequest_set_current_ts(req_msg, current_ts);
        c.kvrpcpb_CleanupRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdCleanup,
            .req = .{ .CmdCleanup = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newBatchRollback(arena: UpbArena, keys: [][]const u8, start_ts: u64) !Request {
        const req_msg = c.kvrpcpb_BatchRollbackRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_BatchRollbackRequest_set_start_version(req_msg, start_ts);

        // Set keys array
        const keys_array = c.kvrpcpb_BatchRollbackRequest_resize_keys(req_msg, keys.len, arena) orelse return error.OutOfMemory;
        for (keys, 0..) |key, i| {
            keys_array[i] = sv(key);
        }

        c.kvrpcpb_BatchRollbackRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdBatchRollback,
            .req = .{ .CmdBatchRollback = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newScanLock(arena: UpbArena, start_key: []const u8, max_ts: u64, limit: u32) !Request {
        const req_msg = c.kvrpcpb_ScanLockRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_ScanLockRequest_set_start_key(req_msg, sv(start_key));
        c.kvrpcpb_ScanLockRequest_set_max_version(req_msg, max_ts);
        c.kvrpcpb_ScanLockRequest_set_limit(req_msg, limit);
        c.kvrpcpb_ScanLockRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdScanLock,
            .req = .{ .CmdScanLock = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newResolveLock(arena: UpbArena, start_ts: u64, commit_ts: u64) !Request {
        const req_msg = c.kvrpcpb_ResolveLockRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_ResolveLockRequest_set_start_version(req_msg, start_ts);
        c.kvrpcpb_ResolveLockRequest_set_commit_version(req_msg, commit_ts);
        c.kvrpcpb_ResolveLockRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdResolveLock,
            .req = .{ .CmdResolveLock = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newGC(arena: UpbArena, safe_point: u64) !Request {
        const req_msg = c.kvrpcpb_GCRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_GCRequest_set_safe_point(req_msg, safe_point);
        c.kvrpcpb_GCRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdGC,
            .req = .{ .CmdGC = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newDeleteRange(arena: UpbArena, start_key: []const u8, end_key: []const u8) !Request {
        const req_msg = c.kvrpcpb_DeleteRangeRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_DeleteRangeRequest_set_start_key(req_msg, sv(start_key));
        c.kvrpcpb_DeleteRangeRequest_set_end_key(req_msg, sv(end_key));
        c.kvrpcpb_DeleteRangeRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdDeleteRange,
            .req = .{ .CmdDeleteRange = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newPessimisticRollback(arena: UpbArena, keys: [][]const u8, start_ts: u64, for_update_ts: u64) !Request {
        const req_msg = c.kvrpcpb_PessimisticRollbackRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_PessimisticRollbackRequest_set_start_version(req_msg, start_ts);
        c.kvrpcpb_PessimisticRollbackRequest_set_for_update_ts(req_msg, for_update_ts);

        // Set keys array
        const keys_array = c.kvrpcpb_PessimisticRollbackRequest_resize_keys(req_msg, keys.len, arena) orelse return error.OutOfMemory;
        for (keys, 0..) |key, i| {
            keys_array[i] = sv(key);
        }

        c.kvrpcpb_PessimisticRollbackRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdPessimisticRollback,
            .req = .{ .CmdPessimisticRollback = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newTxnHeartBeat(arena: UpbArena, primary_lock: []const u8, start_ts: u64, advise_ttl: u64) !Request {
        const req_msg = c.kvrpcpb_TxnHeartBeatRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_TxnHeartBeatRequest_set_primary_lock(req_msg, sv(primary_lock));
        c.kvrpcpb_TxnHeartBeatRequest_set_start_version(req_msg, start_ts);
        c.kvrpcpb_TxnHeartBeatRequest_set_advise_lock_ttl(req_msg, advise_ttl);
        c.kvrpcpb_TxnHeartBeatRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdTxnHeartBeat,
            .req = .{ .CmdTxnHeartBeat = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newCheckTxnStatus(arena: UpbArena, primary_key: []const u8, lock_ts: u64, caller_start_ts: u64, current_ts: u64) !Request {
        const req_msg = c.kvrpcpb_CheckTxnStatusRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_CheckTxnStatusRequest_set_primary_key(req_msg, sv(primary_key));
        c.kvrpcpb_CheckTxnStatusRequest_set_lock_ts(req_msg, lock_ts);
        c.kvrpcpb_CheckTxnStatusRequest_set_caller_start_ts(req_msg, caller_start_ts);
        c.kvrpcpb_CheckTxnStatusRequest_set_current_ts(req_msg, current_ts);
        c.kvrpcpb_CheckTxnStatusRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdCheckTxnStatus,
            .req = .{ .CmdCheckTxnStatus = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    pub fn newCheckSecondaryLocks(arena: UpbArena, keys: [][]const u8, start_ts: u64) !Request {
        const req_msg = c.kvrpcpb_CheckSecondaryLocksRequest_new(arena) orelse return error.OutOfMemory;
        const ctx_msg = c.kvrpcpb_Context_new(arena) orelse return error.OutOfMemory;
        c.kvrpcpb_CheckSecondaryLocksRequest_set_start_version(req_msg, start_ts);

        // Set keys array
        const keys_array = c.kvrpcpb_CheckSecondaryLocksRequest_resize_keys(req_msg, keys.len, arena) orelse return error.OutOfMemory;
        for (keys, 0..) |key, i| {
            keys_array[i] = sv(key);
        }

        c.kvrpcpb_CheckSecondaryLocksRequest_set_context(req_msg, ctx_msg);
        return .{
            .typ = .CmdCheckSecondaryLocks,
            .req = .{ .CmdCheckSecondaryLocks = req_msg },
            .arena = arena,
            .context = ctx_msg,
        };
    }

    // Context setters matching Go version
    pub fn setRegionId(self: *Request, region_id: u64) void {
        c.kvrpcpb_Context_set_region_id(self.context, region_id);
    }

    pub fn setRegionEpoch(self: *Request, conf_ver: u64, version: u64) void {
        const epoch = c.kvrpcpb_Context_mutable_region_epoch(self.context, self.arena) orelse return;
        c.metapb_RegionEpoch_set_conf_ver(epoch, conf_ver);
        c.metapb_RegionEpoch_set_version(epoch, version);
    }

    pub fn setPeer(self: *Request, peer_id: u64, store_id: u64) void {
        const peer = c.kvrpcpb_Context_mutable_peer(self.context, self.arena) orelse return;
        c.metapb_Peer_set_id(peer, peer_id);
        c.metapb_Peer_set_store_id(peer, store_id);
    }

    // Getter methods for transactional KV requests
    pub fn get(self: *const Request) ?*c.kvrpcpb_GetRequest {
        return switch (self.req) {
            .CmdGet => |req| req,
            else => null,
        };
    }

    pub fn scan(self: *const Request) ?*c.kvrpcpb_ScanRequest {
        return switch (self.req) {
            .CmdScan => |req| req,
            else => null,
        };
    }

    pub fn prewrite(self: *const Request) ?*c.kvrpcpb_PrewriteRequest {
        return switch (self.req) {
            .CmdPrewrite => |req| req,
            else => null,
        };
    }

    pub fn commit(self: *const Request) ?*c.kvrpcpb_CommitRequest {
        return switch (self.req) {
            .CmdCommit => |req| req,
            else => null,
        };
    }

    pub fn cleanup(self: *const Request) ?*c.kvrpcpb_CleanupRequest {
        return switch (self.req) {
            .CmdCleanup => |req| req,
            else => null,
        };
    }

    pub fn batchGet(self: *const Request) ?*c.kvrpcpb_BatchGetRequest {
        return switch (self.req) {
            .CmdBatchGet => |req| req,
            else => null,
        };
    }

    pub fn batchRollback(self: *const Request) ?*c.kvrpcpb_BatchRollbackRequest {
        return switch (self.req) {
            .CmdBatchRollback => |req| req,
            else => null,
        };
    }

    pub fn scanLock(self: *const Request) ?*c.kvrpcpb_ScanLockRequest {
        return switch (self.req) {
            .CmdScanLock => |req| req,
            else => null,
        };
    }

    pub fn resolveLock(self: *const Request) ?*c.kvrpcpb_ResolveLockRequest {
        return switch (self.req) {
            .CmdResolveLock => |req| req,
            else => null,
        };
    }

    pub fn gc(self: *const Request) ?*c.kvrpcpb_GCRequest {
        return switch (self.req) {
            .CmdGC => |req| req,
            else => null,
        };
    }

    pub fn deleteRange(self: *const Request) ?*c.kvrpcpb_DeleteRangeRequest {
        return switch (self.req) {
            .CmdDeleteRange => |req| req,
            else => null,
        };
    }

    pub fn pessimisticLock(self: *const Request) ?*c.kvrpcpb_PessimisticLockRequest {
        return switch (self.req) {
            .CmdPessimisticLock => |req| req,
            else => null,
        };
    }

    pub fn pessimisticRollback(self: *const Request) ?*c.kvrpcpb_PessimisticRollbackRequest {
        return switch (self.req) {
            .CmdPessimisticRollback => |req| req,
            else => null,
        };
    }

    pub fn txnHeartBeat(self: *const Request) ?*c.kvrpcpb_TxnHeartBeatRequest {
        return switch (self.req) {
            .CmdTxnHeartBeat => |req| req,
            else => null,
        };
    }

    pub fn checkTxnStatus(self: *const Request) ?*c.kvrpcpb_CheckTxnStatusRequest {
        return switch (self.req) {
            .CmdCheckTxnStatus => |req| req,
            else => null,
        };
    }

    pub fn checkSecondaryLocks(self: *const Request) ?*c.kvrpcpb_CheckSecondaryLocksRequest {
        return switch (self.req) {
            .CmdCheckSecondaryLocks => |req| req,
            else => null,
        };
    }

    // Getter methods for RawKV requests
    pub fn rawGet(self: *const Request) ?*c.kvrpcpb_RawGetRequest {
        return switch (self.req) {
            .CmdRawGet => |req| req,
            else => null,
        };
    }

    pub fn rawPut(self: *const Request) ?*c.kvrpcpb_RawPutRequest {
        return switch (self.req) {
            .CmdRawPut => |req| req,
            else => null,
        };
    }

    pub fn rawDelete(self: *const Request) ?*c.kvrpcpb_RawDeleteRequest {
        return switch (self.req) {
            .CmdRawDelete => |req| req,
            else => null,
        };
    }

    pub fn rawScan(self: *const Request) ?*c.kvrpcpb_RawScanRequest {
        return switch (self.req) {
            .CmdRawScan => |req| req,
            else => null,
        };
    }

    pub fn rawBatchGet(self: *const Request) ?*c.kvrpcpb_RawBatchGetRequest {
        return switch (self.req) {
            .CmdRawBatchGet => |req| req,
            else => null,
        };
    }

    pub fn rawBatchPut(self: *const Request) ?*c.kvrpcpb_RawBatchPutRequest {
        return switch (self.req) {
            .CmdRawBatchPut => |req| req,
            else => null,
        };
    }

    pub fn rawBatchDelete(self: *const Request) ?*c.kvrpcpb_RawBatchDeleteRequest {
        return switch (self.req) {
            .CmdRawBatchDelete => |req| req,
            else => null,
        };
    }

    pub fn rawDeleteRange(self: *const Request) ?*c.kvrpcpb_RawDeleteRangeRequest {
        return switch (self.req) {
            .CmdRawDeleteRange => |req| req,
            else => null,
        };
    }

    pub fn rawGetKeyTTL(self: *const Request) ?*c.kvrpcpb_RawGetKeyTTLRequest {
        return switch (self.req) {
            .CmdGetKeyTTL => |req| req,
            else => null,
        };
    }

    pub fn rawCompareAndSwap(self: *const Request) ?*c.kvrpcpb_RawCASRequest {
        return switch (self.req) {
            .CmdRawCompareAndSwap => |req| req,
            else => null,
        };
    }
};

// Response struct using full protobuf messages
pub const Response = struct {
    typ: CmdType,
    resp: ResponsePayload,
    arena: UpbArena,

    // Getter methods for transactional KV responses
    pub fn get(self: *const Response) ?*c.kvrpcpb_GetResponse {
        return switch (self.resp) {
            .CmdGet => |resp| resp,
            else => null,
        };
    }

    pub fn scan(self: *const Response) ?*c.kvrpcpb_ScanResponse {
        return switch (self.resp) {
            .CmdScan => |resp| resp,
            else => null,
        };
    }

    pub fn prewrite(self: *const Response) ?*c.kvrpcpb_PrewriteResponse {
        return switch (self.resp) {
            .CmdPrewrite => |resp| resp,
            else => null,
        };
    }

    pub fn commit(self: *const Response) ?*c.kvrpcpb_CommitResponse {
        return switch (self.resp) {
            .CmdCommit => |resp| resp,
            else => null,
        };
    }

    pub fn cleanup(self: *const Response) ?*c.kvrpcpb_CleanupResponse {
        return switch (self.resp) {
            .CmdCleanup => |resp| resp,
            else => null,
        };
    }

    pub fn batchGet(self: *const Response) ?*c.kvrpcpb_BatchGetResponse {
        return switch (self.resp) {
            .CmdBatchGet => |resp| resp,
            else => null,
        };
    }

    pub fn batchRollback(self: *const Response) ?*c.kvrpcpb_BatchRollbackResponse {
        return switch (self.resp) {
            .CmdBatchRollback => |resp| resp,
            else => null,
        };
    }

    pub fn scanLock(self: *const Response) ?*c.kvrpcpb_ScanLockResponse {
        return switch (self.resp) {
            .CmdScanLock => |resp| resp,
            else => null,
        };
    }

    pub fn resolveLock(self: *const Response) ?*c.kvrpcpb_ResolveLockResponse {
        return switch (self.resp) {
            .CmdResolveLock => |resp| resp,
            else => null,
        };
    }

    pub fn gc(self: *const Response) ?*c.kvrpcpb_GCResponse {
        return switch (self.resp) {
            .CmdGC => |resp| resp,
            else => null,
        };
    }

    pub fn deleteRange(self: *const Response) ?*c.kvrpcpb_DeleteRangeResponse {
        return switch (self.resp) {
            .CmdDeleteRange => |resp| resp,
            else => null,
        };
    }

    pub fn pessimisticLock(self: *const Response) ?*c.kvrpcpb_PessimisticLockResponse {
        return switch (self.resp) {
            .CmdPessimisticLock => |resp| resp,
            else => null,
        };
    }

    pub fn pessimisticRollback(self: *const Response) ?*c.kvrpcpb_PessimisticRollbackResponse {
        return switch (self.resp) {
            .CmdPessimisticRollback => |resp| resp,
            else => null,
        };
    }

    pub fn txnHeartBeat(self: *const Response) ?*c.kvrpcpb_TxnHeartBeatResponse {
        return switch (self.resp) {
            .CmdTxnHeartBeat => |resp| resp,
            else => null,
        };
    }

    pub fn checkTxnStatus(self: *const Response) ?*c.kvrpcpb_CheckTxnStatusResponse {
        return switch (self.resp) {
            .CmdCheckTxnStatus => |resp| resp,
            else => null,
        };
    }

    pub fn checkSecondaryLocks(self: *const Response) ?*c.kvrpcpb_CheckSecondaryLocksResponse {
        return switch (self.resp) {
            .CmdCheckSecondaryLocks => |resp| resp,
            else => null,
        };
    }

    // Getter methods for RawKV responses
    pub fn rawGet(self: *const Response) ?*c.kvrpcpb_RawGetResponse {
        return switch (self.resp) {
            .CmdRawGet => |resp| resp,
            else => null,
        };
    }

    pub fn rawPut(self: *const Response) ?*c.kvrpcpb_RawPutResponse {
        return switch (self.resp) {
            .CmdRawPut => |resp| resp,
            else => null,
        };
    }

    pub fn rawDelete(self: *const Response) ?*c.kvrpcpb_RawDeleteResponse {
        return switch (self.resp) {
            .CmdRawDelete => |resp| resp,
            else => null,
        };
    }

    pub fn rawScan(self: *const Response) ?*c.kvrpcpb_RawScanResponse {
        return switch (self.resp) {
            .CmdRawScan => |resp| resp,
            else => null,
        };
    }

    pub fn rawBatchPut(self: *const Response) ?*c.kvrpcpb_RawBatchPutResponse {
        return switch (self.resp) {
            .CmdRawBatchPut => |resp| resp,
            else => null,
        };
    }

    pub fn rawBatchGet(self: *const Response) ?*c.kvrpcpb_RawBatchGetResponse {
        return switch (self.resp) {
            .CmdRawBatchGet => |resp| resp,
            else => null,
        };
    }

    pub fn rawBatchDelete(self: *const Response) ?*c.kvrpcpb_RawBatchDeleteResponse {
        return switch (self.resp) {
            .CmdRawBatchDelete => |resp| resp,
            else => null,
        };
    }

    pub fn rawDeleteRange(self: *const Response) ?*c.kvrpcpb_RawDeleteRangeResponse {
        return switch (self.resp) {
            .CmdRawDeleteRange => |resp| resp,
            else => null,
        };
    }

    pub fn rawGetKeyTTL(self: *const Response) ?*c.kvrpcpb_RawGetKeyTTLResponse {
        return switch (self.resp) {
            .CmdGetKeyTTL => |resp| resp,
            else => null,
        };
    }

    pub fn rawCompareAndSwap(self: *const Response) ?*c.kvrpcpb_RawCASResponse {
        return switch (self.resp) {
            .CmdRawCompareAndSwap => |resp| resp,
            else => null,
        };
    }
};

/// SetContext sets the context on the individual protobuf message (matching Go SetContext)
pub fn setContext(req: *Request, region_id: u64, region_epoch_conf_ver: u64, region_epoch_version: u64, peer_id: u64, store_id: u64) void {
    // Set context on the Request struct
    req.setRegionId(region_id);
    req.setRegionEpoch(region_epoch_conf_ver, region_epoch_version);
    req.setPeer(peer_id, store_id);

    // Also set context directly on the individual protobuf message
    req.setContext();
}

/// Create a region error response for the given request type
pub fn genRegionErrorResp(arena: UpbArena, req_typ: CmdType, msg: []const u8) !Response {
    _ = msg; // TODO: Set error message in protobuf
    return switch (req_typ) {
        .CmdRawGet => Response{
            .typ = .CmdRawGet,
            .resp = .{ .CmdRawGet = c.kvrpcpb_RawGetResponse_new(arena) orelse return error.OutOfMemory },
            .arena = arena,
        },
        .CmdRawPut => Response{
            .typ = .CmdRawPut,
            .resp = .{ .CmdRawPut = c.kvrpcpb_RawPutResponse_new(arena) orelse return error.OutOfMemory },
            .arena = arena,
        },
        .CmdRawDelete => Response{
            .typ = .CmdRawDelete,
            .resp = .{ .CmdRawDelete = c.kvrpcpb_RawDeleteResponse_new(arena) orelse return error.OutOfMemory },
            .arena = arena,
        },
        else => return error.UnsupportedCommand,
    };
}

// ---- Tests ----
// test "full protobuf request construction" {
//     const arena = c.upb_Arena_New();
//     defer c.upb_Arena_Free(arena);

//     // Test RawGet construction
//     var req = try Request.newRawGet(arena, "test_key", "default");
//     req.setRegionId(123);
//     req.setRegionEpoch(1, 2);
//     req.setPeer(456, 789);

//     try std.testing.expect(req.typ == .CmdRawGet);

//     // Verify key is set correctly
//     const key_sv = c.kvrpcpb_RawGetRequest_key(req.rawGet());
//     try std.testing.expect(svEqBytes(key_sv, "test_key"));

//     // Verify cf is set correctly
//     const cf_sv = c.kvrpcpb_RawGetRequest_cf(req.rawGet());
//     try std.testing.expect(svEqBytes(cf_sv, "default"));

//     // Verify context is set correctly
//     const region_id = c.kvrpcpb_Context_region_id(req.context);
//     try std.testing.expectEqual(@as(u64, 123), region_id);
// }

// test "full protobuf serialization roundtrip" {
//     const arena = c.upb_Arena_New();
//     defer c.upb_Arena_Free(arena);

//     var req = try Request.newRawPut(arena, "key1", "value1", "default");
//     req.setRegionId(999);

//     // Serialize the request
//     var len: usize = 0;
//     const serialized = c.kvrpcpb_RawPutRequest_serialize(req.rawPut(), arena, &len);
//     try std.testing.expect(len > 0);

//     // Parse it back
//     const arena2 = c.upb_Arena_New();
//     defer c.upb_Arena_Free(arena2);
//     const parsed = c.kvrpcpb_RawPutRequest_parse(serialized, len, arena2) orelse return error.ParseFailed;

//     // Verify fields
//     const key_sv = c.kvrpcpb_RawPutRequest_key(parsed);
//     try std.testing.expect(svEqBytes(key_sv, "key1"));

//     const value_sv = c.kvrpcpb_RawPutRequest_value(parsed);
//     try std.testing.expect(svEqBytes(value_sv, "value1"));
// }

// test "RawBatchPut serialization roundtrip" {
//     const arena = c.upb_Arena_New();
//     defer c.upb_Arena_Free(arena);

//     var keys = [_][]const u8{ "key1", "key2" };
//     var values = [_][]const u8{ "value1", "value2" };
//     var req = try Request.newRawBatchPut(arena, keys[0..], values[0..], "default");

//     // Serialize the request
//     var size: usize = 0;
//     const serialized = c.kvrpcpb_RawBatchPutRequest_serialize(req.rawBatchPut().?, arena, &size);
//     try std.testing.expect(serialized != null);
//     try std.testing.expect(size > 0);

//     // Parse it back
//     const parsed = c.kvrpcpb_RawBatchPutRequest_parse(serialized[0..size].ptr, size, arena);
//     try std.testing.expect(parsed != null);

//     // Verify the parsed request has the same data
//     const parsed_cf = c.kvrpcpb_RawBatchPutRequest_cf(parsed);
//     try std.testing.expect(svEqBytes(parsed_cf, "default"));
// }

// test "Transactional Get serialization roundtrip" {
//     const arena = c.upb_Arena_New();
//     defer c.upb_Arena_Free(arena);

//     var req = try Request.newGet(arena, "test_key", 12345);

//     // Serialize the request
//     var size: usize = 0;
//     const serialized = c.kvrpcpb_GetRequest_serialize(req.get().?, arena, &size);
//     try std.testing.expect(serialized != null);
//     try std.testing.expect(size > 0);

//     // Parse it back
//     const parsed = c.kvrpcpb_GetRequest_parse(serialized[0..size].ptr, size, arena);
//     try std.testing.expect(parsed != null);

//     // Verify the parsed request has the same data
//     const parsed_key = c.kvrpcpb_GetRequest_key(parsed);
//     try std.testing.expect(svEqBytes(parsed_key, "test_key"));

//     const parsed_version = c.kvrpcpb_GetRequest_version(parsed);
//     try std.testing.expect(parsed_version == 12345);
// }

// test "Transactional Prewrite serialization roundtrip" {
//     const arena = c.upb_Arena_New();
//     defer c.upb_Arena_Free(arena);

//     var req = try Request.newPrewrite(arena, "mutations_data", "primary_key", 10000, 60000);

//     // Serialize the request
//     var size: usize = 0;
//     const serialized = c.kvrpcpb_PrewriteRequest_serialize(req.prewrite().?, arena, &size);
//     try std.testing.expect(serialized != null);
//     try std.testing.expect(size > 0);

//     // Parse it back
//     const parsed = c.kvrpcpb_PrewriteRequest_parse(serialized[0..size].ptr, size, arena);
//     try std.testing.expect(parsed != null);

//     // Verify the parsed request has the same data
//     const parsed_primary = c.kvrpcpb_PrewriteRequest_primary_lock(parsed);
//     try std.testing.expect(svEqBytes(parsed_primary, "primary_key"));

//     const parsed_start_ts = c.kvrpcpb_PrewriteRequest_start_version(parsed);
//     try std.testing.expect(parsed_start_ts == 10000);

//     const parsed_lock_ttl = c.kvrpcpb_PrewriteRequest_lock_ttl(parsed);
//     try std.testing.expect(parsed_lock_ttl == 60000);
// }

// test "Transactional Commit serialization roundtrip" {
//     const arena = c.upb_Arena_New();
//     defer c.upb_Arena_Free(arena);

//     var keys = [_][]const u8{ "key1", "key2", "key3" };
//     var req = try Request.newCommit(arena, keys[0..], 10000, 10001);

//     // Serialize the request
//     var size: usize = 0;
//     const serialized = c.kvrpcpb_CommitRequest_serialize(req.commit().?, arena, &size);
//     try std.testing.expect(serialized != null);
//     try std.testing.expect(size > 0);

//     // Parse it back
//     const parsed = c.kvrpcpb_CommitRequest_parse(serialized[0..size].ptr, size, arena);
//     try std.testing.expect(parsed != null);

//     // Verify the parsed request has the same data
//     const parsed_start_ts = c.kvrpcpb_CommitRequest_start_version(parsed);
//     try std.testing.expect(parsed_start_ts == 10000);

//     const parsed_commit_ts = c.kvrpcpb_CommitRequest_commit_version(parsed);
//     try std.testing.expect(parsed_commit_ts == 10001);

//     // Verify keys array
//     var parsed_keys_len: usize = 0;
//     const parsed_keys = c.kvrpcpb_CommitRequest_keys(parsed, &parsed_keys_len);
//     try std.testing.expect(parsed_keys_len == 3);
//     try std.testing.expect(svEqBytes(parsed_keys[0], "key1"));
//     try std.testing.expect(svEqBytes(parsed_keys[1], "key2"));
//     try std.testing.expect(svEqBytes(parsed_keys[2], "key3"));
// }

// test "Transactional BatchGet serialization roundtrip" {
//     const arena = c.upb_Arena_New();
//     defer c.upb_Arena_Free(arena);

//     var keys = [_][]const u8{ "batch_key1", "batch_key2" };
//     var req = try Request.newBatchGet(arena, keys[0..], 20000);

//     // Serialize the request
//     var size: usize = 0;
//     const serialized = c.kvrpcpb_BatchGetRequest_serialize(req.batchGet().?, arena, &size);
//     try std.testing.expect(serialized != null);
//     try std.testing.expect(size > 0);

//     // Parse it back
//     const parsed = c.kvrpcpb_BatchGetRequest_parse(serialized[0..size].ptr, size, arena);
//     try std.testing.expect(parsed != null);

//     // Verify the parsed request has the same data
//     const parsed_version = c.kvrpcpb_BatchGetRequest_version(parsed);
//     try std.testing.expect(parsed_version == 20000);

//     // Verify keys array
//     var parsed_keys_len: usize = 0;
//     const parsed_keys = c.kvrpcpb_BatchGetRequest_keys(parsed, &parsed_keys_len);
//     try std.testing.expect(parsed_keys_len == 2);
//     try std.testing.expect(svEqBytes(parsed_keys[0], "batch_key1"));
//     try std.testing.expect(svEqBytes(parsed_keys[1], "batch_key2"));
// }

// test "PessimisticLock serialization roundtrip" {
//     const arena = c.upb_Arena_New();
//     defer c.upb_Arena_Free(arena);

//     var req = try Request.newPessimisticLock(arena, "mutations", "primary_lock", 30000, 30001, 120000);

//     // Serialize the request
//     var size: usize = 0;
//     const serialized = c.kvrpcpb_PessimisticLockRequest_serialize(req.pessimisticLock().?, arena, &size);
//     try std.testing.expect(serialized != null);
//     try std.testing.expect(size > 0);

//     // Parse it back
//     const parsed = c.kvrpcpb_PessimisticLockRequest_parse(serialized[0..size].ptr, size, arena);
//     try std.testing.expect(parsed != null);

//     // Verify the parsed request has the same data
//     const parsed_primary = c.kvrpcpb_PessimisticLockRequest_primary_lock(parsed);
//     try std.testing.expect(svEqBytes(parsed_primary, "primary_lock"));

//     const parsed_start_ts = c.kvrpcpb_PessimisticLockRequest_start_version(parsed);
//     try std.testing.expect(parsed_start_ts == 30000);

//     const parsed_for_update_ts = c.kvrpcpb_PessimisticLockRequest_for_update_ts(parsed);
//     try std.testing.expect(parsed_for_update_ts == 30001);

//     const parsed_lock_ttl = c.kvrpcpb_PessimisticLockRequest_lock_ttl(parsed);
//     try std.testing.expect(parsed_lock_ttl == 120000);
// }

test "CheckTxnStatus serialization roundtrip" {
    const arena = c.upb_Arena_New();
    defer c.upb_Arena_Free(arena);

    var req = try Request.newCheckTxnStatus(arena, "primary_key", 40000, 40001, 40002);

    // Serialize the request
    var size: usize = 0;
    const serialized = c.kvrpcpb_CheckTxnStatusRequest_serialize(req.checkTxnStatus().?, arena, &size);
    try std.testing.expect(serialized != null);
    try std.testing.expect(size > 0);

    // Parse it back
    const parsed = c.kvrpcpb_CheckTxnStatusRequest_parse(serialized[0..size].ptr, size, arena);
    try std.testing.expect(parsed != null);

    // Verify the parsed request has the same data
    const parsed_primary = c.kvrpcpb_CheckTxnStatusRequest_primary_key(parsed);
    try std.testing.expect(svEqBytes(parsed_primary, "primary_key"));

    const parsed_lock_ts = c.kvrpcpb_CheckTxnStatusRequest_lock_ts(parsed);
    try std.testing.expect(parsed_lock_ts == 40000);

    const parsed_caller_start_ts = c.kvrpcpb_CheckTxnStatusRequest_caller_start_ts(parsed);
    try std.testing.expect(parsed_caller_start_ts == 40001);

    const parsed_current_ts = c.kvrpcpb_CheckTxnStatusRequest_current_ts(parsed);
    try std.testing.expect(parsed_current_ts == 40002);
}
