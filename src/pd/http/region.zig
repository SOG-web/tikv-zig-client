// PD HTTP implementation for GetRegion
const std = @import("std");
const types = @import("../types.zig");
const tctx = @import("../transport_ctx.zig");
const util = @import("util.zig");
const api = @import("api.zig");
const json_helpers = @import("json_helpers.zig");
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

            // Use helper to parse Region from JSON
            return json_helpers.parseRegionFromJson(ctx.allocator, obj) catch |err| {
                if (err == error.OutOfMemory) return Error.OutOfMemory;
                continue; // try next endpoint on parse error
            };
        }
    }

    return Error.RpcError;
}
