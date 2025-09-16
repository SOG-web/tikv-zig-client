// Tests for error handling in TiKV RPC operations
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

test "region error handling in responses" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create a Get response with region error
    const get_resp = c.kvrpcpb_GetResponse_new(@ptrCast(arena.arena)) orelse unreachable;
    const region_error = c.kvrpcpb_GetResponse_mutable_region_error(get_resp, arena.arena) orelse unreachable;
    
    // Set error message
    const error_msg = "region not found";
    c.errorpb_Error_set_message(region_error, .{ .data = error_msg.ptr, .size = error_msg.len });
    
    // Set not leader error
    const not_leader = c.errorpb_Error_mutable_not_leader(region_error, arena.arena) orelse unreachable;
    c.errorpb_NotLeader_set_region_id(not_leader, 100);
    
    // Create leader peer
    const leader = c.errorpb_NotLeader_mutable_leader(not_leader, arena.arena) orelse unreachable;
    c.metapb_Peer_set_id(leader, 200);
    c.metapb_Peer_set_store_id(leader, 300);
    
    // Verify error fields
    const parsed_message = c.errorpb_Error_message(region_error);
    try test_utils.expectStringViewEq(parsed_message, error_msg);
    
    const parsed_not_leader = c.errorpb_Error_not_leader(region_error);
    try std.testing.expect(parsed_not_leader != null);
    
    const parsed_region_id = c.errorpb_NotLeader_region_id(parsed_not_leader);
    try std.testing.expect(parsed_region_id == 100);
    
    const parsed_leader = c.errorpb_NotLeader_leader(parsed_not_leader);
    try std.testing.expect(parsed_leader != null);
    
    const leader_id = c.metapb_Peer_id(parsed_leader);
    const leader_store_id = c.metapb_Peer_store_id(parsed_leader);
    try std.testing.expect(leader_id == 200);
    try std.testing.expect(leader_store_id == 300);
}

test "key error handling in transactional responses" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create a Get response with key error
    const get_resp = c.kvrpcpb_GetResponse_new(@ptrCast(arena.arena)) orelse unreachable;
    const key_error = c.kvrpcpb_GetResponse_mutable_error(get_resp, arena.arena) orelse unreachable;
    
    // Set lock conflict error
    const locked = c.kvrpcpb_KeyError_mutable_locked(key_error, arena.arena) orelse unreachable;
    c.kvrpcpb_LockInfo_set_primary_lock(locked, .{ .data = TestData.keys[5].ptr, .size = TestData.keys[5].len });
    c.kvrpcpb_LockInfo_set_lock_version(locked, TestData.timestamps.start_ts);
    c.kvrpcpb_LockInfo_set_key(locked, .{ .data = TestData.keys[0].ptr, .size = TestData.keys[0].len });
    c.kvrpcpb_LockInfo_set_lock_ttl(locked, TestData.ttl.lock_ttl);
    c.kvrpcpb_LockInfo_set_lock_type(locked, c.kvrpcpb_Op_Put);
    
    // Verify lock info
    const parsed_locked = c.kvrpcpb_KeyError_locked(key_error);
    try std.testing.expect(parsed_locked != null);
    
    const primary_lock = c.kvrpcpb_LockInfo_primary_lock(parsed_locked);
    try test_utils.expectStringViewEq(primary_lock, TestData.keys[5]);
    
    const lock_version = c.kvrpcpb_LockInfo_lock_version(parsed_locked);
    try std.testing.expect(lock_version == TestData.timestamps.start_ts);
    
    const locked_key = c.kvrpcpb_LockInfo_key(parsed_locked);
    try test_utils.expectStringViewEq(locked_key, TestData.keys[0]);
    
    const lock_ttl = c.kvrpcpb_LockInfo_lock_ttl(parsed_locked);
    try std.testing.expect(lock_ttl == TestData.ttl.lock_ttl);
    
    const lock_type = c.kvrpcpb_LockInfo_lock_type(parsed_locked);
    try std.testing.expect(lock_type == c.kvrpcpb_Op_Put);
}

test "write conflict error handling" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create a Prewrite response with write conflict
    const prewrite_resp = c.kvrpcpb_PrewriteResponse_new(arena.arena) orelse unreachable;
    
    // Resize errors array and add write conflict
    const errors_array = c.kvrpcpb_PrewriteResponse_resize_errors(prewrite_resp, 1, arena.arena);
    const key_error = errors_array[0];
    
    const conflict = c.kvrpcpb_KeyError_mutable_conflict(key_error, arena.arena) orelse unreachable;
    c.kvrpcpb_WriteConflict_set_start_ts(conflict, TestData.timestamps.start_ts);
    c.kvrpcpb_WriteConflict_set_conflict_ts(conflict, TestData.timestamps.commit_ts);
    c.kvrpcpb_WriteConflict_set_key(conflict, .{ .data = TestData.keys[0].ptr, .size = TestData.keys[0].len });
    c.kvrpcpb_WriteConflict_set_primary(conflict, .{ .data = TestData.keys[5].ptr, .size = TestData.keys[5].len });
    
    // Verify write conflict
    var errors_len: usize = 0;
    const parsed_errors = c.kvrpcpb_PrewriteResponse_errors(prewrite_resp, &errors_len);
    try std.testing.expect(errors_len == 1);
    
    const parsed_conflict = c.kvrpcpb_KeyError_conflict(parsed_errors[0]);
    try std.testing.expect(parsed_conflict != null);
    
    const conflict_start_ts = c.kvrpcpb_WriteConflict_start_ts(parsed_conflict);
    try std.testing.expect(conflict_start_ts == TestData.timestamps.start_ts);
    
    const conflict_ts = c.kvrpcpb_WriteConflict_conflict_ts(parsed_conflict);
    try std.testing.expect(conflict_ts == TestData.timestamps.commit_ts);
    
    const conflict_key = c.kvrpcpb_WriteConflict_key(parsed_conflict);
    try test_utils.expectStringViewEq(conflict_key, TestData.keys[0]);
    
    const conflict_primary = c.kvrpcpb_WriteConflict_primary(parsed_conflict);
    try test_utils.expectStringViewEq(conflict_primary, TestData.keys[5]);
}

test "deadlock error handling" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create a PessimisticLock response with deadlock error
    const pessimistic_resp = c.kvrpcpb_PessimisticLockResponse_new(@ptrCast(arena.arena)) orelse unreachable;
    
    // Resize errors array and add deadlock
    const errors_array = c.kvrpcpb_PessimisticLockResponse_resize_errors(pessimistic_resp, 1, arena.arena);
    const key_error = errors_array[0];
    
    const deadlock = c.kvrpcpb_KeyError_mutable_deadlock(key_error, arena.arena) orelse unreachable;
    c.kvrpcpb_Deadlock_set_lock_ts(deadlock, TestData.timestamps.start_ts);
    c.kvrpcpb_Deadlock_set_lock_key(deadlock, .{ .data = TestData.keys[0].ptr, .size = TestData.keys[0].len });
    c.kvrpcpb_Deadlock_set_deadlock_key_hash(deadlock, 12345);
    
    // Verify deadlock error
    var errors_len: usize = 0;
    const parsed_errors = c.kvrpcpb_PessimisticLockResponse_errors(pessimistic_resp, &errors_len);
    try std.testing.expect(errors_len == 1);
    
    const parsed_deadlock = c.kvrpcpb_KeyError_deadlock(parsed_errors[0]);
    try std.testing.expect(parsed_deadlock != null);
    
    const deadlock_lock_ts = c.kvrpcpb_Deadlock_lock_ts(parsed_deadlock);
    try std.testing.expect(deadlock_lock_ts == TestData.timestamps.start_ts);
    
    const deadlock_key = c.kvrpcpb_Deadlock_lock_key(parsed_deadlock);
    try test_utils.expectStringViewEq(deadlock_key, TestData.keys[0]);
    
    const deadlock_hash = c.kvrpcpb_Deadlock_deadlock_key_hash(parsed_deadlock);
    try std.testing.expect(deadlock_hash == 12345);
}

test "batch response error propagation" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create a batch response with mixed success and error responses
    const batch_resp = c.tikvpb_BatchCommandsResponse_new(@ptrCast(arena.arena)) orelse unreachable;
    
    // Resize responses array
    const responses_array = c.tikvpb_BatchCommandsResponse_resize_responses(batch_resp, 3, arena.arena);
    
    // First response: successful Get
    const get_resp = c.kvrpcpb_GetResponse_new(@ptrCast(arena.arena)) orelse unreachable;
    c.kvrpcpb_GetResponse_set_value(get_resp, .{ .data = TestData.values[0].ptr, .size = TestData.values[0].len });
    c.tikvpb_BatchCommandsResponse_Response_set_get(responses_array[0], get_resp);
    
    // Second response: Get with region error
    const get_resp_error = c.kvrpcpb_GetResponse_new(@ptrCast(arena.arena)) orelse unreachable;
    const region_error = c.kvrpcpb_GetResponse_mutable_region_error(get_resp_error, arena.arena) orelse unreachable;
    c.errorpb_Error_set_message(region_error, .{ .data = "region not found".ptr, .size = "region not found".len });
    c.tikvpb_BatchCommandsResponse_Response_set_get(responses_array[1], get_resp_error);
    
    // Third response: Prewrite with key error
    const prewrite_resp = c.kvrpcpb_PrewriteResponse_new(@ptrCast(arena.arena)) orelse unreachable;
    const prewrite_errors = c.kvrpcpb_PrewriteResponse_resize_errors(prewrite_resp, 1, arena.arena);
    const locked = c.kvrpcpb_KeyError_mutable_locked(prewrite_errors[0], arena.arena) orelse unreachable;
    c.kvrpcpb_LockInfo_set_key(locked, .{ .data = TestData.keys[0].ptr, .size = TestData.keys[0].len });
    c.kvrpcpb_LockInfo_set_lock_version(locked, TestData.timestamps.start_ts);
    c.tikvpb_BatchCommandsResponse_Response_set_prewrite(responses_array[2], prewrite_resp);
    
    // Parse batch response
    var parsed_responses = std.ArrayList(Response).init(std.testing.allocator);
    defer parsed_responses.deinit();
    
    try batch.fromBatchCommandsResponse(arena.arena, batch_resp, &parsed_responses);
    
    // Verify parsed responses
    try std.testing.expect(parsed_responses.items.len == 3);
    
    // Verify successful Get response
    try std.testing.expect(parsed_responses.items[0].typ == .CmdGet);
    const success_get_resp = parsed_responses.items[0].get().?;
    const success_value = c.kvrpcpb_GetResponse_value(success_get_resp);
    try test_utils.expectStringViewEq(success_value, TestData.values[0]);
    
    // Verify Get response with region error
    try std.testing.expect(parsed_responses.items[1].typ == .CmdGet);
    const error_get_resp = parsed_responses.items[1].get().?;
    const error_region_error = c.kvrpcpb_GetResponse_region_error(error_get_resp);
    try std.testing.expect(error_region_error != null);
    
    // Verify Prewrite response with key error
    try std.testing.expect(parsed_responses.items[2].typ == .CmdPrewrite);
    const error_prewrite_resp = parsed_responses.items[2].prewrite().?;
    var prewrite_errors_len: usize = 0;
    const error_prewrite_errors = c.kvrpcpb_PrewriteResponse_errors(error_prewrite_resp, &prewrite_errors_len);
    try std.testing.expect(prewrite_errors_len == 1);
    
    const error_locked = c.kvrpcpb_KeyError_locked(error_prewrite_errors[0]);
    try std.testing.expect(error_locked != null);
}

test "invalid request parameter handling" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Test empty key handling
    const empty_key = "";
    var req = try Request.newGet(arena.arena, empty_key, TestData.timestamps.start_ts);
    
    const get_req = req.get().?;
    const key = c.kvrpcpb_GetRequest_key(get_req);
    try std.testing.expect(key.size == 0);
    
    // Test zero timestamp
    var req_zero_ts = try Request.newGet(arena.arena, TestData.keys[0], 0);
    const get_req_zero = req_zero_ts.get().?;
    const version = c.kvrpcpb_GetRequest_version(get_req_zero);
    try std.testing.expect(version == 0);
    
    // Test empty keys array for batch operations
    const empty_keys: [][]const u8 = &[_][]const u8{};
    var batch_req = try Request.newBatchGet(arena.arena, empty_keys, TestData.timestamps.start_ts);
    
    const batch_get_req = batch_req.batchGet().?;
    var keys_len: usize = 0;
    const batch_keys = c.kvrpcpb_BatchGetRequest_keys(batch_get_req, &keys_len);
    try std.testing.expect(keys_len == 0);
    try std.testing.expect(batch_keys.len == 0);
}

test "serialization error handling" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create a request and verify serialization works
    var req = try Request.newGet(arena.arena, TestData.keys[0], TestData.timestamps.start_ts);
    const get_req = req.get().?;
    
    // Test normal serialization
    var size: usize = 0;
    const serialized = c.kvrpcpb_GetRequest_serialize(get_req, arena.arena, &size);
    try std.testing.expect(serialized != null);
    try std.testing.expect(size > 0);
    
    // Test parsing with invalid data
    const invalid_data = "invalid protobuf data";
    const parsed_invalid = c.kvrpcpb_GetRequest_parse(invalid_data.ptr, invalid_data.len, arena.arena);
    try std.testing.expect(parsed_invalid == null);
    
    // Test parsing with empty data
    const parsed_empty = c.kvrpcpb_GetRequest_parse(null, 0, arena.arena);
    try std.testing.expect(parsed_empty == null);
}
