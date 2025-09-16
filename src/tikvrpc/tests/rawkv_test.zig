// Tests for RawKV operations
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

test "RawGet request creation and serialization" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create RawGet request
    var req = try Request.newRawGet(arena.arena, TestData.keys[0], "default");
    try std.testing.expect(req.typ == .CmdRawGet);
    
    // Verify getter works
    const raw_get_req = req.rawGet().?;
    const key = c.kvrpcpb_RawGetRequest_key(raw_get_req);
    try test_utils.expectStringViewEq(key, TestData.keys[0]);
    
    const cf = c.kvrpcpb_RawGetRequest_cf(raw_get_req);
    try test_utils.expectStringViewEq(cf, "default");
    
    // Test serialization
    var size: usize = 0;
    const serialized = c.kvrpcpb_RawGetRequest_serialize(raw_get_req, arena.arena, &size);
    try std.testing.expect(serialized != null);
    try std.testing.expect(size > 0);
    
    // Parse back and verify
    const parsed = c.kvrpcpb_RawGetRequest_parse(serialized[0..size].ptr, size, arena.arena);
    try std.testing.expect(parsed != null);
    
    const parsed_key = c.kvrpcpb_RawGetRequest_key(parsed);
    try test_utils.expectStringViewEq(parsed_key, TestData.keys[0]);
    
    const parsed_cf = c.kvrpcpb_RawGetRequest_cf(parsed);
    try test_utils.expectStringViewEq(parsed_cf, "default");
}

test "RawPut request creation and serialization" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create RawPut request
    var req = try Request.newRawPut(arena.arena, TestData.keys[0], TestData.values[0], "default");
    try std.testing.expect(req.typ == .CmdRawPut);
    
    // Verify getter works
    const raw_put_req = req.rawPut().?;
    const key = c.kvrpcpb_RawPutRequest_key(raw_put_req);
    try test_utils.expectStringViewEq(key, TestData.keys[0]);
    
    const value = c.kvrpcpb_RawPutRequest_value(raw_put_req);
    try test_utils.expectStringViewEq(value, TestData.values[0]);
    
    const cf = c.kvrpcpb_RawPutRequest_cf(raw_put_req);
    try test_utils.expectStringViewEq(cf, "default");
    
    // Test serialization
    var size: usize = 0;
    const serialized = c.kvrpcpb_RawPutRequest_serialize(raw_put_req, arena.arena, &size);
    try std.testing.expect(serialized != null);
    try std.testing.expect(size > 0);
}

test "RawDelete request creation and serialization" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create RawDelete request
    var req = try Request.newRawDelete(arena.arena, TestData.keys[0], "default");
    try std.testing.expect(req.typ == .CmdRawDelete);
    
    // Verify getter works
    const raw_delete_req = req.rawDelete().?;
    const key = c.kvrpcpb_RawDeleteRequest_key(raw_delete_req);
    try test_utils.expectStringViewEq(key, TestData.keys[0]);
    
    const cf = c.kvrpcpb_RawDeleteRequest_cf(raw_delete_req);
    try test_utils.expectStringViewEq(cf, "default");
    
    // Test serialization
    var size: usize = 0;
    const serialized = c.kvrpcpb_RawDeleteRequest_serialize(raw_delete_req, arena.arena, &size);
    try std.testing.expect(serialized != null);
    try std.testing.expect(size > 0);
}

test "RawScan request creation and serialization" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create RawScan request
    var req = try Request.newRawScan(arena.arena, TestData.keys[0], TestData.keys[1], 100, false, "default");
    try std.testing.expect(req.typ == .CmdRawScan);
    
    // Verify getter works
    const raw_scan_req = req.rawScan().?;
    const start_key = c.kvrpcpb_RawScanRequest_start_key(raw_scan_req);
    try test_utils.expectStringViewEq(start_key, TestData.keys[0]);
    
    const end_key = c.kvrpcpb_RawScanRequest_end_key(raw_scan_req);
    try test_utils.expectStringViewEq(end_key, TestData.keys[1]);
    
    const limit = c.kvrpcpb_RawScanRequest_limit(raw_scan_req);
    try std.testing.expect(limit == 100);
    
    const key_only = c.kvrpcpb_RawScanRequest_key_only(raw_scan_req);
    try std.testing.expect(key_only == false);
    
    const cf = c.kvrpcpb_RawScanRequest_cf(raw_scan_req);
    try test_utils.expectStringViewEq(cf, "default");
}

test "RawBatchGet request with keys array" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    const keys = [_][]const u8{ TestData.keys[0], TestData.keys[1], TestData.keys[2] };
    
    // Create RawBatchGet request
    var req = try Request.newRawBatchGet(arena.arena, keys[0..], "default");
    try std.testing.expect(req.typ == .CmdRawBatchGet);
    
    // Verify getter works
    const raw_batch_get_req = req.rawBatchGet().?;
    const cf = c.kvrpcpb_RawBatchGetRequest_cf(raw_batch_get_req);
    try test_utils.expectStringViewEq(cf, "default");
    
    // Verify keys array
    var keys_len: usize = 0;
    const batch_keys = c.kvrpcpb_RawBatchGetRequest_keys(raw_batch_get_req, &keys_len);
    try std.testing.expect(keys_len == 3);
    try test_utils.expectStringViewEq(batch_keys[0], TestData.keys[0]);
    try test_utils.expectStringViewEq(batch_keys[1], TestData.keys[1]);
    try test_utils.expectStringViewEq(batch_keys[2], TestData.keys[2]);
}

test "RawBatchPut request with key-value pairs" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    const keys = [_][]const u8{ TestData.keys[0], TestData.keys[1] };
    const values = [_][]const u8{ TestData.values[0], TestData.values[1] };
    
    // Create RawBatchPut request
    var req = try Request.newRawBatchPut(arena.arena, keys[0..], values[0..], "default");
    try std.testing.expect(req.typ == .CmdRawBatchPut);
    
    // Verify getter works
    const raw_batch_put_req = req.rawBatchPut().?;
    const cf = c.kvrpcpb_RawBatchPutRequest_cf(raw_batch_put_req);
    try test_utils.expectStringViewEq(cf, "default");
    
    // Verify pairs array
    var pairs_len: usize = 0;
    const pairs = c.kvrpcpb_RawBatchPutRequest_pairs(raw_batch_put_req, &pairs_len);
    try std.testing.expect(pairs_len == 2);
    
    // Verify first pair
    const first_key = c.kvrpcpb_KvPair_key(pairs[0]);
    const first_value = c.kvrpcpb_KvPair_value(pairs[0]);
    try test_utils.expectStringViewEq(first_key, TestData.keys[0]);
    try test_utils.expectStringViewEq(first_value, TestData.values[0]);
    
    // Verify second pair
    const second_key = c.kvrpcpb_KvPair_key(pairs[1]);
    const second_value = c.kvrpcpb_KvPair_value(pairs[1]);
    try test_utils.expectStringViewEq(second_key, TestData.keys[1]);
    try test_utils.expectStringViewEq(second_value, TestData.values[1]);
}

test "RawBatchDelete request with keys array" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    const keys = [_][]const u8{ TestData.keys[0], TestData.keys[1] };
    
    // Create RawBatchDelete request
    var req = try Request.newRawBatchDelete(arena.arena, keys[0..], "default");
    try std.testing.expect(req.typ == .CmdRawBatchDelete);
    
    // Verify getter works
    const raw_batch_delete_req = req.rawBatchDelete().?;
    const cf = c.kvrpcpb_RawBatchDeleteRequest_cf(raw_batch_delete_req);
    try test_utils.expectStringViewEq(cf, "default");
    
    // Verify keys array
    var keys_len: usize = 0;
    const batch_keys = c.kvrpcpb_RawBatchDeleteRequest_keys(raw_batch_delete_req, &keys_len);
    try std.testing.expect(keys_len == 2);
    try test_utils.expectStringViewEq(batch_keys[0], TestData.keys[0]);
    try test_utils.expectStringViewEq(batch_keys[1], TestData.keys[1]);
}

test "RawDeleteRange request creation" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create RawDeleteRange request
    var req = try Request.newRawDeleteRange(arena.arena, TestData.keys[0], TestData.keys[1], "default");
    try std.testing.expect(req.typ == .CmdRawDeleteRange);
    
    // Verify getter works
    const raw_delete_range_req = req.rawDeleteRange().?;
    const start_key = c.kvrpcpb_RawDeleteRangeRequest_start_key(raw_delete_range_req);
    try test_utils.expectStringViewEq(start_key, TestData.keys[0]);
    
    const end_key = c.kvrpcpb_RawDeleteRangeRequest_end_key(raw_delete_range_req);
    try test_utils.expectStringViewEq(end_key, TestData.keys[1]);
    
    const cf = c.kvrpcpb_RawDeleteRangeRequest_cf(raw_delete_range_req);
    try test_utils.expectStringViewEq(cf, "default");
}

test "RawKV context setting and region management" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create a RawKV request
    var req = try Request.newRawGet(arena.arena, TestData.keys[0], "default");
    
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
    const raw_get_req = req.rawGet().?;
    const req_context = c.kvrpcpb_RawGetRequest_context(raw_get_req);
    try std.testing.expect(req_context != null);
    const req_region_id = c.kvrpcpb_Context_region_id(req_context);
    try std.testing.expect(req_region_id == 100);
}

test "RawKV batch operations in batch commands" {
    var arena = TestArena.init();
    defer arena.deinit();
    
    // Create multiple RawKV requests
    var requests = std.ArrayList(Request){};
    defer requests.deinit(std.testing.allocator);
    
    // Add RawGet request
    const raw_get_req = try Request.newRawGet(arena.arena, TestData.keys[0], "default");
    try requests.append(std.testing.allocator, raw_get_req);
    
    // Add RawPut request
    const raw_put_req = try Request.newRawPut(arena.arena, TestData.keys[1], TestData.values[0], "default");
    try requests.append(std.testing.allocator, raw_put_req);
    
    // Add RawDelete request
    const raw_delete_req = try Request.newRawDelete(arena.arena, TestData.keys[2], "default");
    try requests.append(std.testing.allocator, raw_delete_req);
    
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
    const raw_get_cmd = c.tikvpb_BatchCommandsRequest_Request_raw_get(first_req);
    const get_key = c.kvrpcpb_RawGetRequest_key(raw_get_cmd);
    try test_utils.expectStringViewEq(get_key, TestData.keys[0]);
    
    // Verify RawPut
    const second_req = batch_requests[1];
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_raw_put(second_req));
    const raw_put_cmd = c.tikvpb_BatchCommandsRequest_Request_raw_put(second_req);
    const put_key = c.kvrpcpb_RawPutRequest_key(raw_put_cmd);
    try test_utils.expectStringViewEq(put_key, TestData.keys[1]);
    
    // Verify RawDelete
    const third_req = batch_requests[2];
    try std.testing.expect(c.tikvpb_BatchCommandsRequest_Request_has_raw_delete(third_req));
    const raw_delete_cmd = c.tikvpb_BatchCommandsRequest_Request_raw_delete(third_req);
    const delete_key = c.kvrpcpb_RawDeleteRequest_key(raw_delete_cmd);
    try test_utils.expectStringViewEq(delete_key, TestData.keys[2]);
}
