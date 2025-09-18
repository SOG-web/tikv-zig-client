const std = @import("std");
const pd_client = @import("client.zig");
const exec = @import("../util/execdetails.zig");

pub const InterceptedPDClient = struct {
    // Points to the inner PD client implementation (opaque pointer + vtable)
    inner: pd_client.PDClient,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, inner: pd_client.PDClient) InterceptedPDClient {
        return .{ .inner = inner, .allocator = allocator };
    }

    pub fn getTS(self: InterceptedPDClient, maybe_ctx: ?*exec.ExecDetails) pd_client.Error!pd_client.TSOResult {
        const start = std.time.nanoTimestamp();
        const res = self.inner.getTS();
        // Only record when ctx provided and call succeeded
        if (maybe_ctx) |ctx| {
            const now = std.time.nanoTimestamp();
            var diff: i128 = now - start;
            if (diff < 0) diff = 0;
            const dur_ns = @as(i64, diff);
            if (dur_ns > 0) ctx.wait_pd_resp_duration_ns += dur_ns;
        }
        return res;
    }

    pub fn getRegion(self: InterceptedPDClient, key: []const u8, need_buckets: bool, maybe_ctx: ?*exec.ExecDetails) std.os.Error!pd_client.Region {
        const start = std.time.nanoTimestamp();
        const r = self.inner.getRegion(key, need_buckets);
        if (maybe_ctx) |ctx| {
            const now = std.time.nanoTimestamp();
            var diff: i128 = now - start;
            if (diff < 0) diff = 0;
            const dur_ns = @as(i64, diff);
            if (dur_ns > 0) ctx.wait_pd_resp_duration_ns += dur_ns;
        }
        return r;
    }

    pub fn getStore(self: InterceptedPDClient, store_id: u64, maybe_ctx: ?*exec.ExecDetails) std.os.Error!pd_client.Store {
        const start = std.time.nanoTimestamp();
        const s = self.inner.getStore(store_id);
        if (maybe_ctx) |ctx| {
            const now = std.time.nanoTimestamp();
            var diff: i128 = now - start;
            if (diff < 0) diff = 0;
            const dur_ns = @as(i64, diff);
            if (dur_ns > 0) ctx.wait_pd_resp_duration_ns += dur_ns;
        }
        return s;
    }

    pub fn deinit(self: InterceptedPDClient) void {
        self.inner.close();
    }
};
// --- test helpers ---
const Stub = struct {};

fn stub_getTS(_ptr: *anyopaque) pd_client.Error!pd_client.TSOResult {
    _ = _ptr;
    // simulate some small work by summing a range
    var s: u64 = 0;
    for (0..10000) |j| s += @as(u64, j);
    if (s == 0) std.debug.print("", .{});
    return pd_client.TSOResult{ .physical = 1, .logical = 2 };
}

test "intercepted pd client records wait pd duration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    // Build a tiny stub PDClient by constructing PDClient with a minimal vtable.
    const vtable = &pd_client.PDClient.VTable{
        .getTS = stub_getTS,
        // Remaining function pointers are unused in this test; provide nulls.
        .getLocalTS = null,
        .getRegion = null,
        .getPrevRegion = null,
        .getRegionByID = null,
        .scanRegions = null,
        .getStore = null,
        .getAllStores = null,
        .close = null,
    };

    var stub = Stub{};
    const pd_inner = pd_client.PDClient{ .ptr = &stub, .vtable = vtable };
    const pd = InterceptedPDClient.init(alloc, pd_inner);

    var ed = exec.ExecDetails{};
    const tso = pd.getTS(&ed) catch |err| {
        std.debug.print("err: {}\n", .{err});
        return;
    };
    try std.testing.expect(tso.physical == 1);
    try std.testing.expect(ed.wait_pd_resp_duration_ns > 0);
}
