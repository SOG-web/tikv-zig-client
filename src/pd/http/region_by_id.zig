// PD HTTP implementation for GetRegionByID
const std = @import("std");
const types = @import("../types.zig");
const tctx = @import("../transport_ctx.zig");
const util = @import("util.zig");
const api = @import("api.zig");

const http = util.http;
const Uri = util.Uri;

const Error = types.Error;
const Region = types.Region;

pub fn getRegionByID(ctx: *const tctx.TransportCtx, http_client: *std.http.Client, region_id: u64, need_buckets: bool) Error!Region {
    _ = need_buckets; // HTTP does not provide buckets

    if (ctx.endpoints.len == 0) return Error.InvalidArgument;

    const max_retries: usize = 5;
    var attempt: usize = 0;
    const now_ticks = std.time.nanoTimestamp();
    const start_index: usize = @intCast(@as(u64, @intCast(now_ticks)) % ctx.endpoints.len);

    // region id string
    var id_buf: [32]u8 = undefined;
    const id_str = std.fmt.bufPrint(&id_buf, "{}", .{region_id}) catch unreachable;

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

            const url = try util.buildUrl(ctx.allocator, ctx.use_https, ep, api.RegionByIDPrefixSlash, id_str);
            defer ctx.allocator.free(url);

            aw.clearRetainingCapacity();

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

            const id_val = obj.get("id") orelse {
                continue;
            };
            const start_key_val = obj.get("start_key") orelse {
                continue;
            };
            const end_key_val = obj.get("end_key") orelse {
                continue;
            };

            const id_u64: u64 = @intCast(id_val.integer);
            const start_key_str = start_key_val.string;
            const end_key_str = end_key_val.string;

            const start_key_bytes = try ctx.allocator.dupe(u8, start_key_str);
            const end_key_bytes = try ctx.allocator.dupe(u8, end_key_str);

            return Region{ .id = id_u64, .start_key = start_key_bytes, .end_key = end_key_bytes };
        }
    }

    return Error.RpcError;
}
