const std = @import("std");
const tikvrpc = @import("../mod.zig");
const kvproto = @import("kvproto");
const kvrpcpb = kvproto.kvrpcpb;
const coprocessor = kvproto.coprocessor;
const tikvpb = kvproto.tikvpb;

test "request builders and accessors work" {
    var r = tikvrpc.Request.fromGet(.{ .context = .{}, .key = "k" }, .{ .priority = .high });
    try std.testing.expectEqual(@as(tikvrpc.RequestType, .Get), r.typ);

    const acc = tikvrpc.accessors;
    if (acc.asGet(&r)) |g| {
        try std.testing.expect(std.mem.eql(u8, g.key, "k"));
        g.key = "k2"; // mutate via accessor
    } else return error.TestExpectedGet;
    if (acc.asGetConst(&r)) |gc| {
        try std.testing.expect(std.mem.eql(u8, gc.key, "k2"));
    } else return error.TestExpectedGet;
}

test "codec: toBatchCommandsRequest maps payloads" {
    var get_req = tikvrpc.Request.fromGet(.{ .context = .{}, .key = "kg" }, .{});
    var raw_get_req = tikvrpc.Request.fromRawGet(.{ .context = .{}, .key = "kr" }, .{});

    const bc_get = try tikvrpc.toBatchCommandsRequest(&get_req);
    const bc_raw = try tikvrpc.toBatchCommandsRequest(&raw_get_req);

    try std.testing.expect(bc_get.cmd != null);
    try std.testing.expect(bc_raw.cmd != null);

    switch (bc_get.cmd.?) {
        .Get => |m| try std.testing.expect(std.mem.eql(u8, m.key, "kg")),
        else => return error.TestUnexpectedVariant,
    }
    switch (bc_raw.cmd.?) {
        .RawGet => |m| try std.testing.expect(std.mem.eql(u8, m.key, "kr")),
        else => return error.TestUnexpectedVariant,
    }
}

test "codec: toBatchCommandsRequests builds list and ids" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    var reqs = [_]tikvrpc.Request{
        tikvrpc.Request.fromGet(.{ .context = .{}, .key = "k1" }, .{}),
        tikvrpc.Request.fromRawGet(.{ .context = .{}, .key = "k2" }, .{}),
    };

    var batch = try tikvrpc.toBatchCommandsRequests(A, reqs[0..]);
    defer {
        batch.requests.deinit(A);
        batch.request_ids.deinit(A);
    }
    try std.testing.expectEqual(@as(usize, 2), batch.requests.items.len);
    try std.testing.expectEqual(@as(usize, 2), batch.request_ids.items.len);
    try std.testing.expectEqual(@as(u64, 0), batch.request_ids.items[0]);
    try std.testing.expectEqual(@as(u64, 1), batch.request_ids.items[1]);
}

test "codec: fromBatchCommandsResponse wraps typed response" {
    var resp: tikvpb.BatchCommandsResponse.Response = .{ .cmd = .{ .Get = .{ .value = "vv" } } };
    const wrapped = try tikvrpc.fromBatchCommandsResponse(&resp);
    switch (wrapped.payload) {
        .Get => |m| try std.testing.expect(std.mem.eql(u8, m.value, "vv")),
        else => return error.TestUnexpectedVariant,
    }
}

test "endpoint: callCtx sets context into payload" {
    var ep = tikvrpc.Endpoint.init("127.0.0.1:20160");
    var r = tikvrpc.Request.fromGet(.{ .context = .{}, .key = "k" }, .{});

    var region: kvproto.metapb.Region = .{ .id = 42, .region_epoch = .{} };
    var peer: kvproto.metapb.Peer = .{ .id = 7, .store_id = 9 };
    _ = try ep.callCtx(&r, &region, &peer);

    const acc = tikvrpc.accessors;
    const g = acc.asGetConst(&r) orelse return error.TestExpectedGet;
    try std.testing.expect(g.context != null);
    try std.testing.expectEqual(@as(u64, 42), g.context.?.region_id);
    try std.testing.expect(g.context.?.peer != null);
    try std.testing.expectEqual(@as(u64, 7), g.context.?.peer.?.id);
}

// Module-scope counters for interceptor test
var pre_count: usize = 0;
var post_count: usize = 0;

test "interceptor chain wraps endpoint.call" {
    pre_count = 0; post_count = 0;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var chain = tikvrpc.interceptor.Chain.init(gpa.allocator());
    defer chain.deinit();

    const Hook = struct {
        fn before(_: *const tikvrpc.interceptor.Interceptor, _: []const u8, _: *tikvrpc.Request) void {
            pre_count += 1;
        }
        fn after(_: *const tikvrpc.interceptor.Interceptor, _: []const u8, _: *const tikvrpc.Request, _: *const tikvrpc.CallResult) void {
            post_count += 1;
        }
    };
    var ic = tikvrpc.interceptor.Interceptor{ .beforeSend = Hook.before, .afterRecv = Hook.after };
    _ = chain.link(&ic);

    var ep = tikvrpc.Endpoint.init("127.0.0.1:20160");
    ep.setInterceptorChain(&chain);
    const r = tikvrpc.Request.fromRawGet(.{ .context = .{}, .key = "kk" }, .{});
    _ = try ep.call(r);

    try std.testing.expectEqual(@as(usize, 1), pre_count);
    try std.testing.expectEqual(@as(usize, 1), post_count);
}
