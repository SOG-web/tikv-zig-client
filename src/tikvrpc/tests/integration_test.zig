// Integration tests for complete TiKV RPC workflows
const std = @import("std");
const request = @import("../request.zig");
const batch = @import("../batch.zig");
const test_utils = @import("test_utils.zig");

const Request = request.Request;
const Response = request.Response;
const CmdType = request.CmdType;
const TestArena = test_utils.TestArena;
const TestData = test_utils.TestData;

const c = @import("../../c.zig").c;

test "complete transaction workflow - optimistic transaction" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    var requests = std.ArrayList(Request){};
    defer requests.deinit(std.testing.allocator);
    
    // Step 1: Prewrite phase
    var prewrite_req = try Request.newPrewrite(arena.arena, "mutations", TestData.keys[5], TestData.timestamps.start_ts, TestData.ttl.lock_ttl);
    request.setContext(&prewrite_req, 100, 1, 2, 200, 300);
    try requests.append(std.testing.allocator, prewrite_req);
    
    // Step 2: Commit phase
    const commit_keys = [_][]const u8{ TestData.keys[0], TestData.keys[1] };
    var commit_req = try Request.newCommit(arena.arena, &commit_keys, TestData.timestamps.start_ts, TestData.timestamps.commit_ts);
    request.setContext(&commit_req, 100, 1, 2, 200, 300);
    try requests.append(std.testing.allocator, commit_req);
    
    // Convert to batch and verify
    const batch_req = try batch.toBatchCommandsRequest(arena.arena, requests.items);
    try std.testing.expect(batch_req != null);
    
    var batch_requests_len: usize = 0;
    const batch_requests = c.tikvpb_BatchCommandsRequest_requests(batch_req, &batch_requests_len);
    try std.testing.expect(batch_requests_len == 2);
    
    // Verify prewrite request
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_prewrite(batch_requests[0]));
    const prewrite_cmd = c.tikvpb_BatchCommandsRequest_Request_prewrite(batch_requests[0]);
    const primary_lock = c.kvrpcpb_PrewriteRequest_primary_lock(prewrite_cmd);
    try test_utils.expectStringViewEq(primary_lock, TestData.keys[5]);
    
    // Verify commit request
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_commit(batch_requests[1]));
    const commit_cmd = c.tikvpb_BatchCommandsRequest_Request_commit(batch_requests[1]);
    const commit_start_version = c.kvrpcpb_CommitRequest_start_version(commit_cmd);
    try std.testing.expect(commit_start_version == TestData.timestamps.start_ts);
}

test "complete transaction workflow - pessimistic transaction" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    var requests = std.ArrayList(Request){};
    defer requests.deinit(std.testing.allocator);
    
    // Step 1: Pessimistic lock
    var lock_req = try Request.newPessimisticLock(arena.arena, "mutations", TestData.keys[5], TestData.timestamps.start_ts, TestData.timestamps.for_update_ts, TestData.ttl.lock_ttl);
    request.setContext(&lock_req, 100, 1, 2, 200, 300);
    try requests.append(std.testing.allocator, lock_req);
    
    // Step 2: Prewrite (after acquiring locks)
    var prewrite_req = try Request.newPrewrite(arena.arena, "mutations", TestData.keys[5], TestData.timestamps.start_ts, TestData.ttl.lock_ttl);
    request.setContext(&prewrite_req, 100, 1, 2, 200, 300);
    try requests.append(std.testing.allocator, prewrite_req);
    
    // Step 3: Commit
    const commit_keys = [_][]const u8{ TestData.keys[0], TestData.keys[1] };
    var commit_req = try Request.newCommit(arena.arena, &commit_keys, TestData.timestamps.start_ts, TestData.timestamps.commit_ts);
    request.setContext(&commit_req, 100, 1, 2, 200, 300);
    try requests.append(std.testing.allocator, commit_req);
    
    // Convert to batch and verify
    const batch_req = try batch.toBatchCommandsRequest(arena.arena, requests.items);
    try std.testing.expect(batch_req != null);
    
    var batch_requests_len: usize = 0;
    const batch_requests = c.tikvpb_BatchCommandsRequest_requests(batch_req, &batch_requests_len);
    try std.testing.expect(batch_requests_len == 3);
    
    // Verify pessimistic lock
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_pessimistic_lock(batch_requests[0]));
    
    // Verify prewrite
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_prewrite(batch_requests[1]));
    
    // Verify commit
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_commit(batch_requests[2]));
}

test "transaction rollback workflow" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    var requests = std.ArrayList(Request){};
    defer requests.deinit(std.testing.allocator);
    
    // Step 1: Cleanup primary key
    var cleanup_req = try Request.newCleanup(arena.arena, TestData.keys[5], TestData.timestamps.start_ts, TestData.timestamps.current_ts);
    request.setContext(&cleanup_req, 100, 1, 2, 200, 300);
    try requests.append(std.testing.allocator, cleanup_req);
    
    // Step 2: Batch rollback secondary keys
    const rollback_keys = [_][]const u8{ TestData.keys[0], TestData.keys[1], TestData.keys[2] };
    var rollback_req = try Request.newBatchRollback(arena.arena, &rollback_keys, TestData.timestamps.start_ts);
    request.setContext(&rollback_req, 100, 1, 2, 200, 300);
    try requests.append(std.testing.allocator, rollback_req);
    
    // Convert to batch and verify
    const batch_req = try batch.toBatchCommandsRequest(arena.arena, requests.items);
    try std.testing.expect(batch_req != null);
    
    var batch_requests_len: usize = 0;
    const batch_requests = c.tikvpb_BatchCommandsRequest_requests(batch_req, &batch_requests_len);
    try std.testing.expect(batch_requests_len == 2);
    
    // Verify cleanup request
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_cleanup(batch_requests[0]));
    const cleanup_cmd = c.tikvpb_BatchCommandsRequest_Request_cleanup(batch_requests[0]);
    const cleanup_key = c.kvrpcpb_CleanupRequest_key(cleanup_cmd);
    try test_utils.expectStringViewEq(cleanup_key, TestData.keys[5]);
    
    // Verify batch rollback request
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_batch_rollback(batch_requests[1]));
    const rollback_cmd = c.tikvpb_BatchCommandsRequest_Request_batch_rollback(batch_requests[1]);
    var rollback_keys_len: usize = 0;
    _ = c.kvrpcpb_BatchRollbackRequest_keys(rollback_cmd, &rollback_keys_len);
    try std.testing.expect(rollback_keys_len == 3);
}

test "mixed RawKV and transactional operations" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    var requests = std.ArrayList(Request){};
    defer requests.deinit(std.testing.allocator);
    
    // RawKV operations
    var raw_get_req = try Request.newRawGet(arena.arena, TestData.keys[0], "default");
    request.setContext(&raw_get_req, 100, 1, 2, 200, 300);
    try requests.append(std.testing.allocator, raw_get_req);
    
    var raw_put_req = try Request.newRawPut(arena.arena, TestData.keys[1], TestData.values[0], "default");
    request.setContext(&raw_put_req, 100, 1, 2, 200, 300);
    try requests.append(std.testing.allocator, raw_put_req);
    
    // Transactional operations
    var txn_get_req = try Request.newGet(arena.arena, TestData.keys[2], TestData.timestamps.start_ts);
    request.setContext(&txn_get_req, 100, 1, 2, 200, 300);
    try requests.append(std.testing.allocator, txn_get_req);
    
    const batch_keys = [_][]const u8{ TestData.keys[3], TestData.keys[4] };
    var batch_get_req = try Request.newBatchGet(arena.arena, &batch_keys, TestData.timestamps.start_ts);
    request.setContext(&batch_get_req, 100, 1, 2, 200, 300);
    try requests.append(std.testing.allocator, batch_get_req);
    
    // Convert to batch and verify
    const batch_req = try batch.toBatchCommandsRequest(arena.arena, requests.items);
    try std.testing.expect(batch_req != null);
    
    var batch_requests_len: usize = 0;
    const batch_requests = c.tikvpb_BatchCommandsRequest_requests(batch_req, &batch_requests_len);
    try std.testing.expect(batch_requests_len == 4);
    
    // Verify mixed operations
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_raw_get(batch_requests[0]));
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_raw_put(batch_requests[1]));
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_get(batch_requests[2]));
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_batch_get(batch_requests[3]));
}

test "transaction status monitoring workflow" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    var requests = std.ArrayList(Request){};
    defer requests.deinit(std.testing.allocator);
    
    // Check transaction status
    var check_status_req = try Request.newCheckTxnStatus(arena.arena, TestData.keys[5], TestData.timestamps.start_ts, TestData.timestamps.for_update_ts, TestData.timestamps.current_ts);
    request.setContext(&check_status_req, 100, 1, 2, 200, 300);
    try requests.append(std.testing.allocator, check_status_req);
    
    // Send heartbeat to keep transaction alive
    var heartbeat_req = try Request.newTxnHeartBeat(arena.arena, TestData.keys[5], TestData.timestamps.start_ts, TestData.ttl.advise_ttl);
    request.setContext(&heartbeat_req, 100, 1, 2, 200, 300);
    try requests.append(std.testing.allocator, heartbeat_req);
    
    // Check secondary locks
    const secondary_keys = [_][]const u8{ TestData.keys[6], TestData.keys[7] };
    var check_secondary_req = try Request.newCheckSecondaryLocks(arena.arena, &secondary_keys, TestData.timestamps.start_ts);
    request.setContext(&check_secondary_req, 100, 1, 2, 200, 300);
    try requests.append(std.testing.allocator, check_secondary_req);
    
    // Convert to batch and verify
    const batch_req = try batch.toBatchCommandsRequest(arena.arena, requests.items);
    try std.testing.expect(batch_req != null);
    
    var batch_requests_len: usize = 0;
    const batch_requests = c.tikvpb_BatchCommandsRequest_requests(batch_req, &batch_requests_len);
    try std.testing.expect(batch_requests_len == 3);
    
    // Verify status monitoring operations
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_check_txn_status(batch_requests[0]));
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_txn_heart_beat(batch_requests[1]));
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_check_secondary_locks(batch_requests[2]));
}

test "lock management and resolution workflow" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    var requests = std.ArrayList(Request){};
    defer requests.deinit(std.testing.allocator);
    
    // Scan for locks in a range
    var scan_lock_req = try Request.newScanLock(arena.arena, TestData.keys[0], TestData.timestamps.current_ts, 100);
    request.setContext(&scan_lock_req, 100, 1, 2, 200, 300);
    try requests.append(std.testing.allocator, scan_lock_req);
    
    // Resolve locks found by scan
    var resolve_lock_req = try Request.newResolveLock(arena.arena, TestData.timestamps.start_ts, TestData.timestamps.commit_ts);
    request.setContext(&resolve_lock_req, 100, 1, 2, 200, 300);
    try requests.append(std.testing.allocator, resolve_lock_req);
    
    // Convert to batch and verify
    const batch_req = try batch.toBatchCommandsRequest(arena.arena, requests.items);
    try std.testing.expect(batch_req != null);
    
    var batch_requests_len: usize = 0;
    const batch_requests = c.tikvpb_BatchCommandsRequest_requests(batch_req, &batch_requests_len);
    try std.testing.expect(batch_requests_len == 2);
    
    // Verify lock management operations
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_scan_lock(batch_requests[0]));
    const scan_lock_cmd = c.tikvpb_BatchCommandsRequest_Request_scan_lock(batch_requests[0]);
    const scan_limit = c.kvrpcpb_ScanLockRequest_limit(scan_lock_cmd);
    try std.testing.expect(scan_limit == 100);
    
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_resolve_lock(batch_requests[1]));
    const resolve_lock_cmd = c.tikvpb_BatchCommandsRequest_Request_resolve_lock(batch_requests[1]);
    const resolve_start_version = c.kvrpcpb_ResolveLockRequest_start_version(resolve_lock_cmd);
    try std.testing.expect(resolve_start_version == TestData.timestamps.start_ts);
}

test "garbage collection and maintenance workflow" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    var requests = std.ArrayList(Request){};
    defer requests.deinit(std.testing.allocator);
    
    // Garbage collection
    var gc_req = try Request.newGC(arena.arena, TestData.timestamps.safe_point);
    request.setContext(&gc_req, 100, 1, 2, 200, 300);
    try requests.append(std.testing.allocator, gc_req);
    
    // Delete range for cleanup
    var delete_range_req = try Request.newDeleteRange(arena.arena, TestData.keys[0], TestData.keys[1]);
    request.setContext(&delete_range_req, 100, 1, 2, 200, 300);
    try requests.append(std.testing.allocator, delete_range_req);
    
    // Convert to batch and verify
    const batch_req = try batch.toBatchCommandsRequest(arena.arena, requests.items);
    try std.testing.expect(batch_req != null);
    
    var batch_requests_len: usize = 0;
    const batch_requests = c.tikvpb_BatchCommandsRequest_requests(batch_req, &batch_requests_len);
    try std.testing.expect(batch_requests_len == 2);
    
    // Verify maintenance operations
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_gc(batch_requests[0]));
    const gc_cmd = c.tikvpb_BatchCommandsRequest_Request_gc(batch_requests[0]);
    const safe_point = c.kvrpcpb_GCRequest_safe_point(gc_cmd);
    try std.testing.expect(safe_point == TestData.timestamps.safe_point);
    
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_delete_range(batch_requests[1]));
    const delete_range_cmd = c.tikvpb_BatchCommandsRequest_Request_delete_range(batch_requests[1]);
    const delete_start_key = c.kvrpcpb_DeleteRangeRequest_start_key(delete_range_cmd);
    try test_utils.expectStringViewEq(delete_start_key, TestData.keys[0]);
}

test "large scale batch processing" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    var requests = std.ArrayList(Request){};
    defer requests.deinit(std.testing.allocator);
    
    // Create a large mixed batch
    const batch_size = 50;
    var i: usize = 0;
    while (i < batch_size) : (i += 1) {
        const key_index = i % TestData.keys.len;
        
        if (i % 4 == 0) {
            // RawKV operations
            var raw_req = try Request.newRawGet(arena.arena, TestData.keys[key_index], "default");
            request.setContext(&raw_req, 100, 1, 2, 200, 300);
            try requests.append(std.testing.allocator, raw_req);
        } else if (i % 4 == 1) {
            // Transactional Get
            var txn_req = try Request.newGet(arena.arena, TestData.keys[key_index], TestData.timestamps.start_ts + i);
            request.setContext(&txn_req, 100, 1, 2, 200, 300);
            try requests.append(std.testing.allocator, txn_req);
        } else if (i % 4 == 2) {
            // Scan operations
            const end_key_index = (key_index + 1) % TestData.keys.len;
            var scan_req = try Request.newScan(arena.arena, TestData.keys[key_index], TestData.keys[end_key_index], 10, TestData.timestamps.start_ts + i);
            request.setContext(&scan_req, 100, 1, 2, 200, 300);
            try requests.append(std.testing.allocator, scan_req);
        } else {
            // Cleanup operations
            var cleanup_req = try Request.newCleanup(arena.arena, TestData.keys[key_index], TestData.timestamps.start_ts + i, TestData.timestamps.current_ts + i);
            request.setContext(&cleanup_req, 100, 1, 2, 200, 300);
            try requests.append(std.testing.allocator, cleanup_req);
        }
    }
    
    // Convert to batch
    const start_time = std.time.nanoTimestamp();
    const batch_req = try batch.toBatchCommandsRequest(arena.arena, requests.items);
    const conversion_time = std.time.nanoTimestamp() - start_time;
    
    try std.testing.expect(batch_req != null);
    
    // Verify batch size
    var batch_requests_len: usize = 0;
    const batch_requests = c.tikvpb_BatchCommandsRequest_requests(batch_req, &batch_requests_len);
    try std.testing.expect(batch_requests_len == batch_size);
    
    // Performance check - should handle large batches efficiently
    try std.testing.expect(conversion_time < 50_000_000); // 50ms for 50 requests
    
    std.debug.print("Large batch conversion time for {} requests: {}μs\n", .{ batch_size, conversion_time / 1000 });
    
    // Verify request type distribution
    var raw_count: usize = 0;
    var txn_count: usize = 0;
    var scan_count: usize = 0;
    var cleanup_count: usize = 0;
    
    for (0..batch_size) |idx| {
        if (c.tikvpb_BatchCommandsRequest_Request_has_raw_get(batch_requests[idx])) {
            raw_count += 1;
        } else if (c.tikvpb_BatchCommandsRequest_Request_has_get(batch_requests[idx])) {
            txn_count += 1;
        } else if (c.tikvpb_BatchCommandsRequest_Request_has_scan(batch_requests[idx])) {
            scan_count += 1;
        } else if (c.tikvpb_BatchCommandsRequest_Request_has_cleanup(batch_requests[idx])) {
            cleanup_count += 1;
        }
    }
    
    // Verify distribution matches expected pattern
    try std.testing.expect(raw_count > 0);
    try std.testing.expect(txn_count > 0);
    try std.testing.expect(scan_count > 0);
    try std.testing.expect(cleanup_count > 0);
    try std.testing.expect(raw_count + txn_count + scan_count + cleanup_count == batch_size);
}
