// PD HTTP implementation for GetStore
const std = @import("std");
const types = @import("../types.zig");
const tctx = @import("../transport_ctx.zig");
const util = @import("util.zig");
const api = @import("api.zig");
const json_helpers = @import("json_helpers.zig");

const http = util.http;
const Uri = util.Uri;

const Error = types.Error;
const Store = types.Store;

pub fn getStore(ctx: *const tctx.TransportCtx, http_client: *std.http.Client, store_id: u64) Error!Store {
    if (ctx.endpoints.len == 0) return Error.InvalidArgument;

    const max_retries: usize = 5;
    var attempt: usize = 0;
    const now_ticks = std.time.nanoTimestamp();
    const start_index: usize = @intCast(@as(u64, @intCast(now_ticks)) % ctx.endpoints.len);

    // store id string
    var id_buf: [32]u8 = undefined;
    const id_str = std.fmt.bufPrint(&id_buf, "{}", .{store_id}) catch unreachable;

    while (attempt < max_retries) : (attempt += 1) {
        if (attempt > 0) {
            const backoff_ms = util.jitteredBackoffMs(attempt);
            std.Thread.sleep(backoff_ms * std.time.ns_per_ms);
        }

        var aw: std.Io.Writer.Allocating = std.Io.Writer.Allocating.init(ctx.allocator);
        defer aw.deinit();

        var i: usize = 0;
        while (i < ctx.endpoints.len) : (i += 1) {
            const idx = (start_index + i) % ctx.endpoints.len;
            const ep = ctx.endpoints[idx];

            const url = try util.buildUrl(ctx.allocator, ctx.use_https, ep, api.StorePrefix, id_str);
            defer ctx.allocator.free(url);

            const body = util.fetchGetInto(http_client, url, &aw) catch |err| {
                if (err == error.OutOfMemory) return Error.OutOfMemory;
                continue; // retry next endpoint
            };

            const parsed = std.json.parseFromSlice(std.json.Value, ctx.allocator, body, .{ .allocate = .alloc_always }) catch |err| {
                if (err == error.OutOfMemory) return Error.OutOfMemory;
                return Error.RpcError;
            };
            defer parsed.deinit();

            const obj = parsed.value.object;

            // Use helper to parse Store from wrapped JSON
            return json_helpers.parseStoreFromWrappedJson(ctx.allocator, obj) catch |err| {
                if (err == error.OutOfMemory) return Error.OutOfMemory;
                continue; // try next endpoint on parse error
            };
        }
    }

    return Error.RpcError;
}
