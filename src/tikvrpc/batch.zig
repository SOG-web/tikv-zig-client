// TikvRPC Batch mapping for RawKV using full protobuf messages
// This file handles conversion between individual requests and tikvpb.BatchCommandsRequest,
// matching the Go client-go/tikvrpc batch handling exactly.
const std = @import("std");
const request = @import("request.zig");
const c = @import("../c.zig").c;

const Request = request.Request;
const Response = request.Response;
const CmdType = request.CmdType;
const UpbArena = [*c]c.upb_Arena;

/// Convert a single Request to a tikvpb.BatchCommandsRequest.Request protobuf message
pub fn toBatchCommandsRequest(arena: UpbArena, req: *const Request) !*c.tikvpb_BatchCommandsRequest_Request {
    const batch_req = c.tikvpb_BatchCommandsRequest_Request_new(arena) orelse return error.OutOfMemory;

    switch (req.typ) {
        // Transactional KV operations
        .CmdGet => {
            const get_req = req.get() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_get(batch_req, get_req);
        },
        .CmdScan => {
            const scan_req = req.scan() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_scan(batch_req, scan_req);
        },
        .CmdPrewrite => {
            const prewrite_req = req.prewrite() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_prewrite(batch_req, prewrite_req);
        },
        .CmdCommit => {
            const commit_req = req.commit() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_commit(batch_req, commit_req);
        },
        .CmdCleanup => {
            const cleanup_req = req.cleanup() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_cleanup(batch_req, cleanup_req);
        },
        .CmdBatchGet => {
            const batch_get_req = req.batchGet() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_batch_get(batch_req, batch_get_req);
        },
        .CmdBatchRollback => {
            const batch_rollback_req = req.batchRollback() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_batch_rollback(batch_req, batch_rollback_req);
        },
        .CmdScanLock => {
            const scan_lock_req = req.scanLock() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_scan_lock(batch_req, scan_lock_req);
        },
        .CmdResolveLock => {
            const resolve_lock_req = req.resolveLock() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_resolve_lock(batch_req, resolve_lock_req);
        },
        .CmdGC => {
            const gc_req = req.gc() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_gc(batch_req, gc_req);
        },
        .CmdDeleteRange => {
            const delete_range_req = req.deleteRange() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_delete_range(batch_req, delete_range_req);
        },
        .CmdPessimisticLock => {
            const pessimistic_lock_req = req.pessimisticLock() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_pessimistic_lock(batch_req, pessimistic_lock_req);
        },
        .CmdPessimisticRollback => {
            const pessimistic_rollback_req = req.pessimisticRollback() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_pessimistic_rollback(batch_req, pessimistic_rollback_req);
        },
        .CmdTxnHeartBeat => {
            const txn_heartbeat_req = req.txnHeartBeat() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_txn_heart_beat(batch_req, txn_heartbeat_req);
        },
        .CmdCheckTxnStatus => {
            const check_txn_status_req = req.checkTxnStatus() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_check_txn_status(batch_req, check_txn_status_req);
        },
        .CmdCheckSecondaryLocks => {
            const check_secondary_locks_req = req.checkSecondaryLocks() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_check_secondary_locks(batch_req, check_secondary_locks_req);
        },

        // RawKV operations
        .CmdRawGet => {
            const raw_get = req.rawGet() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_raw_get(batch_req, raw_get);
        },
        .CmdRawPut => {
            const raw_put = req.rawPut() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_raw_put(batch_req, raw_put);
        },
        .CmdRawDelete => {
            const raw_delete = req.rawDelete() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_raw_delete(batch_req, raw_delete);
        },
        .CmdRawScan => {
            const raw_scan = req.rawScan() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_raw_scan(batch_req, raw_scan);
        },
        .CmdRawBatchGet => {
            const raw_batch_get = req.rawBatchGet() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_raw_batch_get(batch_req, raw_batch_get);
        },
        .CmdRawBatchPut => {
            const raw_batch_put = req.rawBatchPut() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_raw_batch_put(batch_req, raw_batch_put);
        },
        .CmdRawBatchDelete => {
            const raw_batch_delete = req.rawBatchDelete() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_raw_batch_delete(batch_req, raw_batch_delete);
        },
        .CmdRawDeleteRange => {
            const raw_delete_range = req.rawDeleteRange() orelse return error.InvalidRequest;
            c.tikvpb_BatchCommandsRequest_Request_set_raw_delete_range(batch_req, raw_delete_range);
        },
        .CmdGetKeyTTL => {
            // TODO: Verify if RawGetKeyTTL has batch setter in protobuf
            return error.UnsupportedCommand;
        },
        .CmdRawCompareAndSwap => {
            // TODO: Verify if RawCompareAndSwap has batch setter in protobuf
            return error.UnsupportedCommand;
        },
        else => {
            return error.UnsupportedCommand;
        },
    }
    return batch_req;
}

// test "batch commands request conversion" {
//     const arena = c.upb_Arena_New();
//     defer c.upb_Arena_Free(arena);

//     // Create sample requests
//     const req1 = try Request.newRawGet(arena, "key1", "default");
//     const req2 = try Request.newRawPut(arena, "key2", "value2", "default");

//     const reqs = [_]Request{ req1, req2 };

//     // Convert to batch
//     const batch_msg = try createBatchCommandsRequest(&reqs, arena);

//     // Verify batch structure
//     var req_count: usize = 0;
//     const req_array = c.tikvpb_BatchCommandsRequest_requests(batch_msg, &req_count);
//     try std.testing.expectEqual(@as(usize, 2), req_count);

//     // Verify first request is RawGet
//     const first_req = req_array[0];
//     const cmd_case = c.tikvpb_BatchCommandsRequest_Request_cmd_case(first_req);
//     try std.testing.expect(cmd_case == c.tikvpb_BatchCommandsRequest_Request_cmd_RawGet);

//     // Verify second request is RawPut
//     const second_req = req_array[1];
//     const cmd_case2 = c.tikvpb_BatchCommandsRequest_Request_cmd_case(second_req);
//     try std.testing.expect(cmd_case2 == c.tikvpb_BatchCommandsRequest_Request_cmd_RawPut);
// }

// test "single request to batch conversion" {
//     const arena = c.upb_Arena_New();
//     defer c.upb_Arena_Free(arena);

//     var req = try Request.newRawDelete(arena, "delete_key", "default");

//     const batch_req = try toBatchCommandsRequest(arena, &req);

//     // Verify it's a RawDelete command
//     const cmd_case = c.tikvpb_BatchCommandsRequest_Request_cmd_case(batch_req);
//     try std.testing.expect(cmd_case == c.tikvpb_BatchCommandsRequest_Request_cmd_RawDelete);

//     // Verify the embedded RawDelete request
//     const raw_delete = c.tikvpb_BatchCommandsRequest_Request_RawDelete(batch_req);
//     try std.testing.expect(raw_delete != null);
// }

/// Create a full tikvpb.BatchCommandsRequest with multiple requests
pub fn createBatchCommandsRequest(reqs: []const Request, arena: UpbArena) !*c.tikvpb_BatchCommandsRequest {
    const batch_msg = c.tikvpb_BatchCommandsRequest_new(arena) orelse return error.OutOfMemory;

    // Resize requests array
    const req_array = c.tikvpb_BatchCommandsRequest_resize_requests(batch_msg, reqs.len, arena) orelse return error.OutOfMemory;

    // Fill each request
    for (reqs, 0..) |req, i| {
        req_array[i] = try toBatchCommandsRequest(arena, &req);
    }

    return batch_msg;
}

/// Parse a single tikvpb.BatchCommandsResponse.Response back into a Zig Response
fn parseSingleResponse(batch_resp: *const c.tikvpb_BatchCommandsResponse_Response, arena: UpbArena) !Response {
    // Check which oneof field is set in the batch response
    const case = c.tikvpb_BatchCommandsResponse_Response_cmd_case(batch_resp);

    return switch (case) {
        // Transactional KV responses
        c.tikvpb_BatchCommandsResponse_Response_cmd_Get => {
            const get_resp = c.tikvpb_BatchCommandsResponse_Response_get(batch_resp);
            return Response{
                .typ = .CmdGet,
                .resp = .{ .CmdGet = get_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_Scan => {
            const scan_resp = c.tikvpb_BatchCommandsResponse_Response_scan(batch_resp);
            return Response{
                .typ = .CmdScan,
                .resp = .{ .CmdScan = scan_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_Prewrite => {
            const prewrite_resp = c.tikvpb_BatchCommandsResponse_Response_prewrite(batch_resp);
            return Response{
                .typ = .CmdPrewrite,
                .resp = .{ .CmdPrewrite = prewrite_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_Commit => {
            const commit_resp = c.tikvpb_BatchCommandsResponse_Response_commit(batch_resp);
            return Response{
                .typ = .CmdCommit,
                .resp = .{ .CmdCommit = commit_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_Cleanup => {
            const cleanup_resp = c.tikvpb_BatchCommandsResponse_Response_cleanup(batch_resp);
            return Response{
                .typ = .CmdCleanup,
                .resp = .{ .CmdCleanup = cleanup_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_BatchGet => {
            const batch_get_resp = c.tikvpb_BatchCommandsResponse_Response_batch_get(batch_resp);
            return Response{
                .typ = .CmdBatchGet,
                .resp = .{ .CmdBatchGet = batch_get_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_BatchRollback => {
            const batch_rollback_resp = c.tikvpb_BatchCommandsResponse_Response_batch_rollback(batch_resp);
            return Response{
                .typ = .CmdBatchRollback,
                .resp = .{ .CmdBatchRollback = batch_rollback_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_ScanLock => {
            const scan_lock_resp = c.tikvpb_BatchCommandsResponse_Response_scan_lock(batch_resp);
            return Response{
                .typ = .CmdScanLock,
                .resp = .{ .CmdScanLock = scan_lock_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_ResolveLock => {
            const resolve_lock_resp = c.tikvpb_BatchCommandsResponse_Response_resolve_lock(batch_resp);
            return Response{
                .typ = .CmdResolveLock,
                .resp = .{ .CmdResolveLock = resolve_lock_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_GC => {
            const gc_resp = c.tikvpb_BatchCommandsResponse_Response_gc(batch_resp);
            return Response{
                .typ = .CmdGC,
                .resp = .{ .CmdGC = gc_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_DeleteRange => {
            const delete_range_resp = c.tikvpb_BatchCommandsResponse_Response_delete_range(batch_resp);
            return Response{
                .typ = .CmdDeleteRange,
                .resp = .{ .CmdDeleteRange = delete_range_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_PessimisticLock => {
            const pessimistic_lock_resp = c.tikvpb_BatchCommandsResponse_Response_pessimistic_lock(batch_resp);
            return Response{
                .typ = .CmdPessimisticLock,
                .resp = .{ .CmdPessimisticLock = pessimistic_lock_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_PessimisticRollback => {
            const pessimistic_rollback_resp = c.tikvpb_BatchCommandsResponse_Response_pessimistic_rollback(batch_resp);
            return Response{
                .typ = .CmdPessimisticRollback,
                .resp = .{ .CmdPessimisticRollback = pessimistic_rollback_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_TxnHeartBeat => {
            const txn_heartbeat_resp = c.tikvpb_BatchCommandsResponse_Response_txn_heart_beat(batch_resp);
            return Response{
                .typ = .CmdTxnHeartBeat,
                .resp = .{ .CmdTxnHeartBeat = txn_heartbeat_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_CheckTxnStatus => {
            const check_txn_status_resp = c.tikvpb_BatchCommandsResponse_Response_check_txn_status(batch_resp);
            return Response{
                .typ = .CmdCheckTxnStatus,
                .resp = .{ .CmdCheckTxnStatus = check_txn_status_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_CheckSecondaryLocks => {
            const check_secondary_locks_resp = c.tikvpb_BatchCommandsResponse_Response_check_secondary_locks(batch_resp);
            return Response{
                .typ = .CmdCheckSecondaryLocks,
                .resp = .{ .CmdCheckSecondaryLocks = check_secondary_locks_resp },
                .arena = arena,
            };
        },

        // RawKV responses
        c.tikvpb_BatchCommandsResponse_Response_cmd_RawGet => {
            const raw_get_resp = c.tikvpb_BatchCommandsResponse_Response_raw_get(batch_resp);
            return Response{
                .typ = .CmdRawGet,
                .resp = .{ .CmdRawGet = raw_get_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_RawPut => {
            const raw_put_resp = c.tikvpb_BatchCommandsResponse_Response_raw_put(batch_resp);
            return Response{
                .typ = .CmdRawPut,
                .resp = .{ .CmdRawPut = raw_put_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_RawDelete => {
            const raw_delete_resp = c.tikvpb_BatchCommandsResponse_Response_raw_delete(batch_resp);
            return Response{
                .typ = .CmdRawDelete,
                .resp = .{ .CmdRawDelete = raw_delete_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_RawScan => {
            const raw_scan_resp = c.tikvpb_BatchCommandsResponse_Response_raw_scan(batch_resp);
            return Response{
                .typ = .CmdRawScan,
                .resp = .{ .CmdRawScan = raw_scan_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_RawBatchGet => {
            const raw_batch_get_resp = c.tikvpb_BatchCommandsResponse_Response_raw_batch_get(batch_resp);
            return Response{
                .typ = .CmdRawBatchGet,
                .resp = .{ .CmdRawBatchGet = raw_batch_get_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_RawBatchPut => {
            const raw_batch_put_resp = c.tikvpb_BatchCommandsResponse_Response_raw_batch_put(batch_resp);
            return Response{
                .typ = .CmdRawBatchPut,
                .resp = .{ .CmdRawBatchPut = raw_batch_put_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_RawBatchDelete => {
            const raw_batch_delete_resp = c.tikvpb_BatchCommandsResponse_Response_raw_batch_delete(batch_resp);
            return Response{
                .typ = .CmdRawBatchDelete,
                .resp = .{ .CmdRawBatchDelete = raw_batch_delete_resp },
                .arena = arena,
            };
        },
        c.tikvpb_BatchCommandsResponse_Response_cmd_RawDeleteRange => {
            const raw_delete_range_resp = c.tikvpb_BatchCommandsResponse_Response_raw_delete_range(batch_resp);
            return Response{
                .typ = .CmdRawDeleteRange,
                .resp = .{ .CmdRawDeleteRange = raw_delete_range_resp },
                .arena = arena,
            };
        },
        else => {
            return error.UnsupportedResponse;
        },
    };
}

// test "batch response parsing" {
//     const arena = c.upb_Arena_New();
//     defer c.upb_Arena_Free(arena);

//     // Create a mock batch response with RawGet
//     const batch_resp = c.tikvpb_BatchCommandsResponse_Response_new(arena) orelse return error.OutOfMemory;
//     const raw_get_resp = c.kvrpcpb_RawGetResponse_new(arena) orelse return error.OutOfMemory;
//     c.tikvpb_BatchCommandsResponse_Response_set_RawGet(batch_resp, raw_get_resp);

//     // Parse it back
//     const parsed = try parseSingleResponse(batch_resp, arena);
//     try std.testing.expect(parsed.typ == .CmdRawGet);

//     // Verify we can access the response
//     const resp = parsed.rawGet();
//     try std.testing.expect(resp != null);
// }
