// Tests for batch commands functionality
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

test "batch commands request conversion - transactional operations" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create multiple transactional requests
    var requests = std.ArrayList(Request){};
    defer requests.deinit(std.testing.allocator);
    
    // Add Get request
    const get_req = try Request.newGet(arena.arena, TestData.keys[0], TestData.timestamps.start_ts);
    try requests.append(std.testing.allocator, get_req);
    
    // Add Prewrite request
    const prewrite_req = try Request.newPrewrite(arena.arena, "mutations", TestData.keys[5], TestData.timestamps.start_ts, TestData.ttl.lock_ttl);
    try requests.append(std.testing.allocator, prewrite_req);
    
    // Add Commit request
    const commit_keys = [_][]const u8{ TestData.keys[0], TestData.keys[1] };
    const commit_req = try Request.newCommit(arena.arena, &commit_keys, TestData.timestamps.start_ts, TestData.timestamps.commit_ts);
    try requests.append(std.testing.allocator, commit_req);
    
    // Convert to batch commands request
    const batch_req = try batch.toBatchCommandsRequest(arena.arena, requests.items);
    try std.testing.expect(batch_req != null);
    
    // Verify batch request structure
    var requests_len: usize = 0;
    const batch_requests = c.tikvpb_BatchCommandsRequest_requests(batch_req, &requests_len);
    try std.testing.expect(requests_len == 3);
    
    // Verify first request (Get)
    const first_req = batch_requests[0];
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_get(first_req));
    const get_cmd = c.tikvpb_BatchCommandsRequest_Request_get(first_req);
    const get_key = c.kvrpcpb_GetRequest_key(get_cmd);
    try test_utils.expectStringViewEq(get_key, TestData.keys[0]);
    
    // Verify second request (Prewrite)
    const second_req = batch_requests[1];
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_prewrite(second_req));
    const prewrite_cmd = c.tikvpb_BatchCommandsRequest_Request_prewrite(second_req);
    const primary_lock = c.kvrpcpb_PrewriteRequest_primary_lock(prewrite_cmd);
    try test_utils.expectStringViewEq(primary_lock, TestData.keys[5]);
    
    // Verify third request (Commit)
    const third_req = batch_requests[2];
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_commit(third_req));
    const commit_cmd = c.tikvpb_BatchCommandsRequest_Request_commit(third_req);
    const commit_start_version = c.kvrpcpb_CommitRequest_start_version(commit_cmd);
    try std.testing.expect(commit_start_version == TestData.timestamps.start_ts);
}

test "batch commands request conversion - mixed RawKV and transactional" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    var requests = std.ArrayList(Request){};
    defer requests.deinit(std.testing.allocator);
    
    // Add RawGet request
    const raw_get_req = try Request.newRawGet(arena.arena, TestData.keys[0], "default");
    try requests.append(std.testing.allocator, raw_get_req);
    
    // Add transactional BatchGet request
    const batch_keys = [_][]const u8{ TestData.keys[1], TestData.keys[2] };
    const batch_get_req = try Request.newBatchGet(arena.arena, &batch_keys, TestData.timestamps.start_ts);
    try requests.append(std.testing.allocator, batch_get_req);
    
    // Add RawPut request
    const raw_put_req = try Request.newRawPut(arena.arena, TestData.keys[3], TestData.values[0], "default");
    try requests.append(std.testing.allocator, raw_put_req);
    
    // Convert to batch commands request
    const batch_req = try batch.toBatchCommandsRequest(arena.arena, requests.items);
    try std.testing.expect(batch_req != null);
    
    // Verify batch request structure
    var requests_len: usize = 0;
    const batch_requests = c.tikvpb_BatchCommandsRequest_requests(batch_req, &requests_len);
    try std.testing.expect(requests_len == 3);
    
    // Verify RawGet
    const first_req = batch_requests[0];
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_raw_get(first_req));
    
    // Verify BatchGet
    const second_req = batch_requests[1];
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_batch_get(second_req));
    
    // Verify RawPut
    const third_req = batch_requests[2];
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_raw_put(third_req));
}

test "batch commands response parsing - transactional responses" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create a batch response with transactional responses
    const batch_resp = c.tikvpb_BatchCommandsResponse_new(@ptrCast(arena.arena)) orelse unreachable;
    
    // Resize responses array
    const responses_array = c.tikvpb_BatchCommandsResponse_resize_responses(batch_resp, 3, arena.arena);
    
    // Create Get response
    const get_resp = c.kvrpcpb_GetResponse_new(arena.arena) orelse unreachable;
    c.kvrpcpb_GetResponse_set_value(get_resp, .{ .data = TestData.values[0].ptr, .size = TestData.values[0].len });
    c.tikvpb_BatchCommandsResponse_Response_set_get(responses_array[0], get_resp);
    
    // Create Prewrite response
    const prewrite_resp = c.kvrpcpb_PrewriteResponse_new(@ptrCast(arena.arena)) orelse unreachable;
    c.tikvpb_BatchCommandsResponse_Response_set_prewrite(responses_array[1], prewrite_resp);
    
    // Create Commit response
    const commit_resp = c.kvrpcpb_CommitResponse_new(@ptrCast(arena.arena)) orelse unreachable;
    c.tikvpb_BatchCommandsResponse_Response_set_commit(responses_array[2], commit_resp);
    
    // Parse batch response
    var parsed_responses = std.ArrayList(Response).init(std.testing.allocator);
    defer parsed_responses.deinit();
    
    try batch.fromBatchCommandsResponse(arena.arena, batch_resp, &parsed_responses);
    
    // Verify parsed responses
    try std.testing.expect(parsed_responses.items.len == 3);
    
    // Verify Get response
    try std.testing.expect(parsed_responses.items[0].typ == .CmdGet);
    const parsed_get_resp = parsed_responses.items[0].get().?;
    const get_value = c.kvrpcpb_GetResponse_value(parsed_get_resp);
    try test_utils.expectStringViewEq(get_value, TestData.values[0]);
    
    // Verify Prewrite response
    try std.testing.expect(parsed_responses.items[1].typ == .CmdPrewrite);
    const parsed_prewrite_resp = parsed_responses.items[1].prewrite().?;
    try std.testing.expect(parsed_prewrite_resp != null);
    
    // Verify Commit response
    try std.testing.expect(parsed_responses.items[2].typ == .CmdCommit);
    const parsed_commit_resp = parsed_responses.items[2].commit().?;
    try std.testing.expect(parsed_commit_resp != null);
}

test "batch commands response parsing - error handling" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create a batch response with region errors
    const batch_resp = c.tikvpb_BatchCommandsResponse_new(@ptrCast(arena.arena)) orelse unreachable;
    
    // Resize responses array
    const responses_array = c.tikvpb_BatchCommandsResponse_resize_responses(batch_resp, 2, arena.arena);
    
    // Create Get response with region error
    const get_resp = c.kvrpcpb_GetResponse_new(arena.arena) orelse unreachable;
    const region_error = c.kvrpcpb_GetResponse_mutable_region_error(get_resp, arena.arena) orelse unreachable;
    c.errorpb_Error_set_message(region_error, .{ .data = "region not found".ptr, .size = "region not found".len });
    c.tikvpb_BatchCommandsResponse_Response_set_get(responses_array[0], get_resp);
    
    // Create normal Scan response
    const scan_resp = c.kvrpcpb_ScanResponse_new(arena.arena) orelse unreachable;
    c.tikvpb_BatchCommandsResponse_Response_set_scan(responses_array[1], scan_resp);
    
    // Parse batch response
    var parsed_responses = std.ArrayList(Response).init(std.testing.allocator);
    defer parsed_responses.deinit();
    
    try batch.fromBatchCommandsResponse(arena.arena, batch_resp, &parsed_responses);
    
    // Verify parsed responses
    try std.testing.expect(parsed_responses.items.len == 2);
    
    // Verify Get response with error
    try std.testing.expect(parsed_responses.items[0].typ == .CmdGet);
    const parsed_get_resp = parsed_responses.items[0].get().?;
    const get_region_error = c.kvrpcpb_GetResponse_region_error(parsed_get_resp);
    try std.testing.expect(get_region_error != null);
    const error_message = c.errorpb_Error_message(get_region_error);
    try test_utils.expectStringViewEq(error_message, "region not found");
    
    // Verify normal Scan response
    try std.testing.expect(parsed_responses.items[1].typ == .CmdScan);
}

test "batch commands roundtrip - full serialization cycle" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create original requests
    var original_requests = std.ArrayList(Request){};
    defer original_requests.deinit(std.testing.allocator);
    
    // Add Get request
    var get_req = try Request.newGet(arena.arena, TestData.keys[0], TestData.timestamps.start_ts);
    request.setContext(&get_req, 100, 1, 2, 200, 300);
    try original_requests.append(std.testing.allocator, get_req);
    
    var scan_req = try Request.newScan(arena.arena, TestData.keys[1], TestData.keys[2], 50, TestData.timestamps.start_ts);
    request.setContext(&scan_req, 100, 1, 2, 200, 300);
    try original_requests.append(std.testing.allocator, scan_req);
    
    // Convert to batch request
    const batch_req = try batch.toBatchCommandsRequest(arena.arena, original_requests.items);
    
    // Serialize batch request
    var size: usize = 0;
    const serialized = c.tikvpb_BatchCommandsRequest_serialize(batch_req, arena.arena, &size);
    try std.testing.expect(serialized != null);
    try std.testing.expect(size > 0);
    
    // Parse serialized data back
    const parsed_batch_req = c.tikvpb_BatchCommandsRequest_parse(serialized[0..size].ptr, size, arena.arena);
    try std.testing.expect(parsed_batch_req != null);
    
    // Verify parsed batch request
    var parsed_requests_len: usize = 0;
    const parsed_requests = c.tikvpb_BatchCommandsRequest_requests(parsed_batch_req, &parsed_requests_len);
    try std.testing.expect(parsed_requests_len == 2);
    
    // Verify first request (Get)
    const first_req = parsed_requests[0];
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_get(first_req));
    const get_cmd = c.tikvpb_BatchCommandsRequest_Request_get(first_req);
    const get_key = c.kvrpcpb_GetRequest_key(get_cmd);
    try test_utils.expectStringViewEq(get_key, TestData.keys[0]);
    
    const get_version = c.kvrpcpb_GetRequest_version(get_cmd);
    try std.testing.expect(get_version == TestData.timestamps.start_ts);
    
    // Verify context was preserved
    const get_context = c.kvrpcpb_GetRequest_context(get_cmd);
    try std.testing.expect(get_context != null);
    const get_region_id = c.kvrpcpb_Context_region_id(get_context);
    try std.testing.expect(get_region_id == 100);
    
    // Verify second request (Scan)
    const second_req = parsed_requests[1];
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_scan(second_req));
    const scan_cmd = c.tikvpb_BatchCommandsRequest_Request_scan(second_req);
    const scan_start_key = c.kvrpcpb_ScanRequest_start_key(scan_cmd);
    try test_utils.expectStringViewEq(scan_start_key, TestData.keys[1]);
    
    const scan_limit = c.kvrpcpb_ScanRequest_limit(scan_cmd);
    try std.testing.expect(scan_limit == 50);
}

test "batch commands performance - large batch handling" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create a large batch of requests
    var requests = std.ArrayList(Request){};
    defer requests.deinit(std.testing.allocator);
    
    const batch_size = 100;
    var i: usize = 0;
    while (i < batch_size) : (i += 1) {
        const key_index = i % TestData.keys.len;
        const req = try Request.newGet(arena.arena, TestData.keys[key_index], TestData.timestamps.start_ts + i);
        try requests.append(std.testing.allocator, req);
    }
    
    // Convert to batch commands request
    const start_time = std.time.nanoTimestamp();
    const batch_req = try batch.toBatchCommandsRequest(arena.arena, requests.items);
    const conversion_time = std.time.nanoTimestamp() - start_time;
    
    try std.testing.expect(batch_req != null);
    
    // Verify batch size
    var requests_len: usize = 0;
    _ = c.tikvpb_BatchCommandsRequest_requests(batch_req, &requests_len);
    try std.testing.expect(requests_len == batch_size);
    
    // Performance check - conversion should be reasonably fast
    // Allow up to 10ms for 100 requests (100μs per request)
    try std.testing.expect(conversion_time < 10_000_000); // 10ms in nanoseconds
    
    std.debug.print("Batch conversion time for {} requests: {}μs\n", .{ batch_size, conversion_time / 1000 });
}
