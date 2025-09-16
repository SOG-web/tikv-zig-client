// PD HTTP implementation for GetRegion
const std = @import("std");
const types = @import("../types.zig");
const tctx = @import("../transport_ctx.zig");
const util = @import("util.zig");
const api = @import("api.zig");
const http = std.http;
const json = std.json;

const Error = types.Error;
const Region = types.Region;

// TODO(cascade): Empty key behavior — we early-return NotFound to avoid 404 spam.
// Consider auto-fallback to `scanRegions("", "\xff", 1)` and return the first region
// if present, and verify parity against the Go pd-client behavior.

pub fn getRegion(
    ctx: *const tctx.TransportCtx,
    http_client: *std.http.Client,
    key: []const u8,
    need_buckets: bool,
) Error!Region {
    _ = need_buckets;

    if (ctx.endpoints.len == 0) return Error.InvalidArgument;

    // Empty key has no path segment to append; PD will return 404. Treat as not found.
    if (key.len == 0) return Error.NotFound;

    const max_retries: usize = 5;
    var attempt: usize = 0;
    const now_ticks = std.time.nanoTimestamp();
    const start_index: usize = @intCast(@as(u64, @intCast(now_ticks)) % ctx.endpoints.len);

    var enc_buf = std.ArrayList(u8){};
    defer enc_buf.deinit(ctx.allocator);
    try util.percentEncode(&enc_buf, ctx.allocator, key);
    const escaped_key = enc_buf.items;

    while (attempt < max_retries) : (attempt += 1) {
        if (attempt > 0) {
            const backoff_ms = util.jitteredBackoffMs(attempt);
            std.Thread.sleep(backoff_ms * std.time.ns_per_ms);
        }

        // Reuse a single allocating writer across endpoints in this attempt
        var aw: std.Io.Writer.Allocating = std.Io.Writer.Allocating.init(ctx.allocator);
        defer aw.deinit();

        var i: usize = 0;
        while (i < ctx.endpoints.len) : (i += 1) {
            const idx = (start_index + i) % ctx.endpoints.len;
            const ep = ctx.endpoints[idx];

            // buildUrl allocates; make sure to free it manually on all code paths
            const url = try util.buildUrl(ctx.allocator, ctx.use_https, ep, api.RegionByKeyPrefix, escaped_key);
            defer ctx.allocator.free(url);

            // Fetch body via reusable helper
            const body = util.fetchGetInto(http_client, url, &aw) catch |err| {
                if (err == error.OutOfMemory) return Error.OutOfMemory;
                continue; // treat other errors as retryable to next endpoint
            };

            // parse JSON using body (parser will allocate via ctx.allocator)
            const parsed = json.parseFromSlice(json.Value, ctx.allocator, body, .{ .allocate = .alloc_always }) catch |err| {
                // log the exact error for debugging
                std.log.err("json.parseFromSlice failed: {s}", .{@errorName(err)});

                // preserve OOM
                if (err == error.OutOfMemory) return Error.OutOfMemory;

                // collapse the rest into RpcError
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

            // copy out the keys into ctx.allocator (these can fail -> propagate OutOfMemory)
            const start_key_bytes = try ctx.allocator.dupe(u8, start_key_str);
            const end_key_bytes = try ctx.allocator.dupe(u8, end_key_str);

            return Region{ .id = id_u64, .start_key = start_key_bytes, .end_key = end_key_bytes };
        }
    }

    return Error.RpcError;
}
