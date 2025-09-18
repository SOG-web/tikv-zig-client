// PD HTTP implementation for ScanRegions
const std = @import("std");
const types = @import("../types.zig");
const tctx = @import("../transport_ctx.zig");
const util = @import("util.zig");
const api = @import("api.zig");

const http = util.http;
const Uri = util.Uri;

const Error = types.Error;
const Region = types.Region;

pub fn scanRegions(ctx: *const tctx.TransportCtx, http_client: *std.http.Client, start_key: []const u8, end_key: []const u8, limit: usize) Error![]Region {
    if (ctx.endpoints.len == 0) return Error.InvalidArgument;

    const max_retries: usize = 5;
    var attempt: usize = 0;
    const now_ticks = std.time.nanoTimestamp();
    const start_index: usize = @intCast(@as(u64, @intCast(now_ticks)) % ctx.endpoints.len);

    // Percent-encode start and end keys for query params
    var enc_start = std.ArrayList(u8){};
    defer enc_start.deinit(ctx.allocator);
    try util.percentEncode(&enc_start, ctx.allocator, start_key);

    var enc_end = std.ArrayList(u8){};
    defer enc_end.deinit(ctx.allocator);
    try util.percentEncode(&enc_end, ctx.allocator, end_key);

    // limit to string
    var lim_buf: [32]u8 = undefined;
    const lim_str = std.fmt.bufPrint(&lim_buf, "{}", .{limit}) catch unreachable;

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

            // Build query tail: ?key=<start>&end_key=<end>&limit=<n>
            var tail = std.ArrayList(u8){};
            defer tail.deinit(ctx.allocator);
            try tail.appendSlice(ctx.allocator, "?key=");
            try tail.appendSlice(ctx.allocator, enc_start.items);
            try tail.appendSlice(ctx.allocator, "&end_key=");
            try tail.appendSlice(ctx.allocator, enc_end.items);
            try tail.appendSlice(ctx.allocator, "&limit=");
            try tail.appendSlice(ctx.allocator, lim_str);

            const url = try util.buildUrl(ctx.allocator, ctx.use_https, ep, api.RegionsByKey, tail.items);
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

            const regions_val = obj.get("regions") orelse {
                // Some PD versions may return empty set differently; return empty
                return ctx.allocator.alloc(Region, 0);
            };

            const arr = regions_val.array;
            var out = std.ArrayList(Region){};
            errdefer {
                // free any partially appended regions
                for (out.items) |r| {
                    ctx.allocator.free(r.start_key);
                    ctx.allocator.free(r.end_key);
                }
                out.deinit(ctx.allocator);
            }

            for (arr.items) |item| {
                const r_obj = item.object;
                const id_val = r_obj.get("id") orelse continue;
                const start_key_val = r_obj.get("start_key") orelse continue;
                const end_key_val = r_obj.get("end_key") orelse continue;

                const id_u64: u64 = @intCast(id_val.integer);
                const sk_str = start_key_val.string;
                const ek_str = end_key_val.string;
                const sk = try ctx.allocator.dupe(u8, sk_str);
                const ek = try ctx.allocator.dupe(u8, ek_str);

                try out.append(ctx.allocator, .{ .id = id_u64, .start_key = sk, .end_key = ek });
                if (out.items.len >= limit) break; // extra safety if PD returns more
            }

            const result = out.toOwnedSlice(ctx.allocator);

            return result;
        }
    }

    return Error.RpcError;
}
