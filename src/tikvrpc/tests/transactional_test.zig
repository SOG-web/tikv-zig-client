// Comprehensive tests for transactional TiKV RPC operations
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

test "transactional Get request creation and serialization" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create Get request
    var req = try Request.newGet(arena.arena, TestData.keys[0], TestData.timestamps.start_ts);
    try std.testing.expect(req.typ == .CmdGet);
    
    // Verify getter works
    const get_req = req.get().?;
    const key = c.kvrpcpb_GetRequest_key(get_req);
    try test_utils.expectStringViewEq(key, TestData.keys[0]);
    
    const version = c.kvrpcpb_GetRequest_version(get_req);
    try std.testing.expect(version == TestData.timestamps.start_ts);
    
    // Test serialization
    var size: usize = 0;
    const serialized = c.kvrpcpb_GetRequest_serialize(get_req, arena.arena, &size);
    try std.testing.expect(serialized != null);
    try std.testing.expect(size > 0);
    
    // Parse back and verify
    const parsed = c.kvrpcpb_GetRequest_parse(serialized[0..size].ptr, size, arena.arena);
    try std.testing.expect(parsed != null);
    
    const parsed_key = c.kvrpcpb_GetRequest_key(parsed);
    try test_utils.expectStringViewEq(parsed_key, TestData.keys[0]);
    
    const parsed_version = c.kvrpcpb_GetRequest_version(parsed);
    try std.testing.expect(parsed_version == TestData.timestamps.start_ts);
}

test "transactional Scan request creation and serialization" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create Scan request
    var req = try Request.newScan(arena.arena, TestData.keys[0], TestData.keys[1], 100, TestData.timestamps.start_ts);
    try std.testing.expect(req.typ == .CmdScan);
    
    // Verify getter works
    const scan_req = req.scan().?;
    const start_key = c.kvrpcpb_ScanRequest_start_key(scan_req);
    try test_utils.expectStringViewEq(start_key, TestData.keys[0]);
    
    const end_key = c.kvrpcpb_ScanRequest_end_key(scan_req);
    try test_utils.expectStringViewEq(end_key, TestData.keys[1]);
    
    const limit = c.kvrpcpb_ScanRequest_limit(scan_req);
    try std.testing.expect(limit == 100);
    
    const version = c.kvrpcpb_ScanRequest_version(scan_req);
    try std.testing.expect(version == TestData.timestamps.start_ts);
}

test "transactional Prewrite request creation and serialization" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create Prewrite request
    var req = try Request.newPrewrite(arena.arena, "mutations_data", TestData.keys[5], TestData.timestamps.start_ts, TestData.ttl.lock_ttl);
    try std.testing.expect(req.typ == .CmdPrewrite);
    
    // Verify getter works
    const prewrite_req = req.prewrite().?;
    const primary_lock = c.kvrpcpb_PrewriteRequest_primary_lock(prewrite_req);
    try test_utils.expectStringViewEq(primary_lock, TestData.keys[5]);
    
    const start_version = c.kvrpcpb_PrewriteRequest_start_version(prewrite_req);
    try std.testing.expect(start_version == TestData.timestamps.start_ts);
    
    const lock_ttl = c.kvrpcpb_PrewriteRequest_lock_ttl(prewrite_req);
    try std.testing.expect(lock_ttl == TestData.ttl.lock_ttl);
    
    // Test serialization
    var size: usize = 0;
    const serialized = c.kvrpcpb_PrewriteRequest_serialize(prewrite_req, arena.arena, &size);
    try std.testing.expect(serialized != null);
    try std.testing.expect(size > 0);
}

test "transactional Commit request with keys array" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    const keys = [_][]const u8{ TestData.keys[0], TestData.keys[1], TestData.keys[2] };
    
    // Create Commit request
    var req = try Request.newCommit(arena.arena, keys[0..], TestData.timestamps.start_ts, TestData.timestamps.commit_ts);
    try std.testing.expect(req.typ == .CmdCommit);
    
    // Verify getter works
    const commit_req = req.commit().?;
    const start_version = c.kvrpcpb_CommitRequest_start_version(commit_req);
    try std.testing.expect(start_version == TestData.timestamps.start_ts);
    
    const commit_version = c.kvrpcpb_CommitRequest_commit_version(commit_req);
    try std.testing.expect(commit_version == TestData.timestamps.commit_ts);
    
    // Verify keys array
    var keys_len: usize = 0;
    const commit_keys = c.kvrpcpb_CommitRequest_keys(commit_req, &keys_len);
    try std.testing.expect(keys_len == 3);
    try test_utils.expectStringViewEq(commit_keys[0], TestData.keys[0]);
    try test_utils.expectStringViewEq(commit_keys[1], TestData.keys[1]);
    try test_utils.expectStringViewEq(commit_keys[2], TestData.keys[2]);
}

test "transactional BatchGet request with keys array" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    const keys = [_][]const u8{ TestData.keys[3], TestData.keys[4] };
    
    // Create BatchGet request
    var req = try Request.newBatchGet(arena.arena, keys[0..], TestData.timestamps.start_ts);
    try std.testing.expect(req.typ == .CmdBatchGet);
    
    // Verify getter works
    const batch_get_req = req.batchGet().?;
    const version = c.kvrpcpb_BatchGetRequest_version(batch_get_req);
    try std.testing.expect(version == TestData.timestamps.start_ts);
    
    // Verify keys array
    var keys_len: usize = 0;
    const batch_keys = c.kvrpcpb_BatchGetRequest_keys(batch_get_req, &keys_len);
    try std.testing.expect(keys_len == 2);
    try test_utils.expectStringViewEq(batch_keys[0], TestData.keys[3]);
    try test_utils.expectStringViewEq(batch_keys[1], TestData.keys[4]);
}

test "pessimistic locking operations" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Test PessimisticLock
    var lock_req = try Request.newPessimisticLock(arena.arena, "mutations", TestData.keys[5], TestData.timestamps.start_ts, TestData.timestamps.for_update_ts, TestData.ttl.lock_ttl);
    try std.testing.expect(lock_req.typ == .CmdPessimisticLock);
    
    const pessimistic_lock_req = lock_req.pessimisticLock().?;
    const primary_lock = c.kvrpcpb_PessimisticLockRequest_primary_lock(pessimistic_lock_req);
    try test_utils.expectStringViewEq(primary_lock, TestData.keys[5]);
    
    const start_version = c.kvrpcpb_PessimisticLockRequest_start_version(pessimistic_lock_req);
    try std.testing.expect(start_version == TestData.timestamps.start_ts);
    
    const for_update_ts = c.kvrpcpb_PessimisticLockRequest_for_update_ts(pessimistic_lock_req);
    try std.testing.expect(for_update_ts == TestData.timestamps.for_update_ts);
    
    // Test PessimisticRollback
    const rollback_keys = [_][]const u8{ TestData.keys[6], TestData.keys[7] };
    var rollback_req = try Request.newPessimisticRollback(arena.arena, rollback_keys[0..], TestData.timestamps.start_ts, TestData.timestamps.for_update_ts);
    try std.testing.expect(rollback_req.typ == .CmdPessimisticRollback);
    
    const pessimistic_rollback_req = rollback_req.pessimisticRollback().?;
    const rollback_start_version = c.kvrpcpb_PessimisticRollbackRequest_start_version(pessimistic_rollback_req);
    try std.testing.expect(rollback_start_version == TestData.timestamps.start_ts);
    
    // Verify keys array
    var rollback_keys_len: usize = 0;
    const rollback_keys_array = c.kvrpcpb_PessimisticRollbackRequest_keys(pessimistic_rollback_req, &rollback_keys_len);
    try std.testing.expect(rollback_keys_len == 2);
    try test_utils.expectStringViewEq(rollback_keys_array[0], TestData.keys[6]);
    try test_utils.expectStringViewEq(rollback_keys_array[1], TestData.keys[7]);
}

test "transaction status and management operations" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Test CheckTxnStatus
    var check_status_req = try Request.newCheckTxnStatus(arena.arena, TestData.keys[5], TestData.timestamps.start_ts, TestData.timestamps.for_update_ts, TestData.timestamps.current_ts);
    try std.testing.expect(check_status_req.typ == .CmdCheckTxnStatus);
    
    const check_txn_status_req = check_status_req.checkTxnStatus().?;
    const primary_key = c.kvrpcpb_CheckTxnStatusRequest_primary_key(check_txn_status_req);
    try test_utils.expectStringViewEq(primary_key, TestData.keys[5]);
    
    const lock_ts = c.kvrpcpb_CheckTxnStatusRequest_lock_ts(check_txn_status_req);
    try std.testing.expect(lock_ts == TestData.timestamps.start_ts);
    
    // Test TxnHeartBeat
    var heartbeat_req = try Request.newTxnHeartBeat(arena.arena, TestData.keys[5], TestData.timestamps.start_ts, TestData.ttl.advise_ttl);
    try std.testing.expect(heartbeat_req.typ == .CmdTxnHeartBeat);
    
    const txn_heartbeat_req = heartbeat_req.txnHeartBeat().?;
    const heartbeat_primary = c.kvrpcpb_TxnHeartBeatRequest_primary_lock(txn_heartbeat_req);
    try test_utils.expectStringViewEq(heartbeat_primary, TestData.keys[5]);
    
    const heartbeat_start_version = c.kvrpcpb_TxnHeartBeatRequest_start_version(txn_heartbeat_req);
    try std.testing.expect(heartbeat_start_version == TestData.timestamps.start_ts);
    
    const advise_lock_ttl = c.kvrpcpb_TxnHeartBeatRequest_advise_lock_ttl(txn_heartbeat_req);
    try std.testing.expect(advise_lock_ttl == TestData.ttl.advise_ttl);
    
    // Test CheckSecondaryLocks
    const secondary_keys = [_][]const u8{ TestData.keys[6], TestData.keys[7] };
    var check_secondary_req = try Request.newCheckSecondaryLocks(arena.arena, secondary_keys[0..], TestData.timestamps.start_ts);
    try std.testing.expect(check_secondary_req.typ == .CmdCheckSecondaryLocks);
    
    const check_secondary_locks_req = check_secondary_req.checkSecondaryLocks().?;
    const secondary_start_version = c.kvrpcpb_CheckSecondaryLocksRequest_start_version(check_secondary_locks_req);
    try std.testing.expect(secondary_start_version == TestData.timestamps.start_ts);
    
    // Verify keys array
    var secondary_keys_len: usize = 0;
    const secondary_keys_array = c.kvrpcpb_CheckSecondaryLocksRequest_keys(check_secondary_locks_req, &secondary_keys_len);
    try std.testing.expect(secondary_keys_len == 2);
    try test_utils.expectStringViewEq(secondary_keys_array[0], TestData.keys[6]);
    try test_utils.expectStringViewEq(secondary_keys_array[1], TestData.keys[7]);
}

test "lock management operations" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Test ScanLock
    var scan_lock_req = try Request.newScanLock(arena.arena, TestData.keys[0], TestData.timestamps.current_ts, 50);
    try std.testing.expect(scan_lock_req.typ == .CmdScanLock);
    
    const scan_lock_request = scan_lock_req.scanLock().?;
    const start_key = c.kvrpcpb_ScanLockRequest_start_key(scan_lock_request);
    try test_utils.expectStringViewEq(start_key, TestData.keys[0]);
    
    const max_version = c.kvrpcpb_ScanLockRequest_max_version(scan_lock_request);
    try std.testing.expect(max_version == TestData.timestamps.current_ts);
    
    const limit = c.kvrpcpb_ScanLockRequest_limit(scan_lock_request);
    try std.testing.expect(limit == 50);
    
    // Test ResolveLock
    var resolve_lock_req = try Request.newResolveLock(arena.arena, TestData.timestamps.start_ts, TestData.timestamps.commit_ts);
    try std.testing.expect(resolve_lock_req.typ == .CmdResolveLock);
    
    const resolve_lock_request = resolve_lock_req.resolveLock().?;
    const resolve_start_version = c.kvrpcpb_ResolveLockRequest_start_version(resolve_lock_request);
    try std.testing.expect(resolve_start_version == TestData.timestamps.start_ts);
    
    const resolve_commit_version = c.kvrpcpb_ResolveLockRequest_commit_version(resolve_lock_request);
    try std.testing.expect(resolve_commit_version == TestData.timestamps.commit_ts);
}

test "cleanup and maintenance operations" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Test Cleanup
    var cleanup_req = try Request.newCleanup(arena.arena, TestData.keys[0], TestData.timestamps.start_ts, TestData.timestamps.current_ts);
    try std.testing.expect(cleanup_req.typ == .CmdCleanup);
    
    const cleanup_request = cleanup_req.cleanup().?;
    const cleanup_key = c.kvrpcpb_CleanupRequest_key(cleanup_request);
    try test_utils.expectStringViewEq(cleanup_key, TestData.keys[0]);
    
    const cleanup_start_version = c.kvrpcpb_CleanupRequest_start_version(cleanup_request);
    try std.testing.expect(cleanup_start_version == TestData.timestamps.start_ts);
    
    const cleanup_current_ts = c.kvrpcpb_CleanupRequest_current_ts(cleanup_request);
    try std.testing.expect(cleanup_current_ts == TestData.timestamps.current_ts);
    
    // Test BatchRollback
    const rollback_keys = [_][]const u8{ TestData.keys[0], TestData.keys[1] };
    var batch_rollback_req = try Request.newBatchRollback(arena.arena, rollback_keys[0..], TestData.timestamps.start_ts);
    try std.testing.expect(batch_rollback_req.typ == .CmdBatchRollback);
    
    const batch_rollback_request = batch_rollback_req.batchRollback().?;
    const rollback_start_version = c.kvrpcpb_BatchRollbackRequest_start_version(batch_rollback_request);
    try std.testing.expect(rollback_start_version == TestData.timestamps.start_ts);
    
    // Test GC
    var gc_req = try Request.newGC(arena.arena, TestData.timestamps.safe_point);
    try std.testing.expect(gc_req.typ == .CmdGC);
    
    const gc_request = gc_req.gc().?;
    const safe_point = c.kvrpcpb_GCRequest_safe_point(gc_request);
    try std.testing.expect(safe_point == TestData.timestamps.safe_point);
    
    // Test DeleteRange
    var delete_range_req = try Request.newDeleteRange(arena.arena, TestData.keys[0], TestData.keys[1]);
    try std.testing.expect(delete_range_req.typ == .CmdDeleteRange);
    
    const delete_range_request = delete_range_req.deleteRange().?;
    const delete_start_key = c.kvrpcpb_DeleteRangeRequest_start_key(delete_range_request);
    try test_utils.expectStringViewEq(delete_start_key, TestData.keys[0]);
    
    const delete_end_key = c.kvrpcpb_DeleteRangeRequest_end_key(delete_range_request);
    try test_utils.expectStringViewEq(delete_end_key, TestData.keys[1]);
}

test "context setting and region management" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create a transactional request
    var req = try Request.newGet(arena.arena, TestData.keys[0], TestData.timestamps.start_ts);
    
    // Set context using the helper function
    request.setContext(&req, 100, 1, 2, 200, 300);
    
    // Verify context was set correctly
    const region_id = c.kvrpcpb_Context_region_id(req.context);
    try std.testing.expect(region_id == 100);
    
    const region_epoch = c.kvrpcpb_Context_region_epoch(req.context);
    try std.testing.expect(region_epoch != null);
    const conf_ver = c.metapb_RegionEpoch_conf_ver(region_epoch);
    const version = c.metapb_RegionEpoch_version(region_epoch);
    try std.testing.expect(conf_ver == 1);
    try std.testing.expect(version == 2);
    
    const peer = c.kvrpcpb_Context_peer(req.context);
    try std.testing.expect(peer != null);
    const peer_id = c.metapb_Peer_id(peer);
    const store_id = c.metapb_Peer_store_id(peer);
    try std.testing.expect(peer_id == 200);
    try std.testing.expect(store_id == 300);
    
    // Verify the context was also set on the individual request message
    const get_req = req.get().?;
    const req_context = c.kvrpcpb_GetRequest_context(get_req);
    try std.testing.expect(req_context != null);
    const req_region_id = c.kvrpcpb_Context_region_id(req_context);
    try std.testing.expect(req_region_id == 100);
}
