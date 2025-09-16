const std = @import("std");
const oracle = @import("../mod.zig");

fn parseEndpoints(alloc: std.mem.Allocator) ![][]const u8 {
    const ep_env = std.process.getEnvVarOwned(alloc, "PD_ENDPOINT") catch |e| switch (e) {
        error.EnvironmentVariableNotFound => null,
        else => return e,
    };
    defer if (ep_env) |s| alloc.free(s);

    var eps = std.ArrayList([]const u8){};
    errdefer eps.deinit(alloc);

    if (ep_env) |s| {
        var it = std.mem.splitScalar(u8, s, ',');
        while (it.next()) |piece| {
            if (piece.len == 0) continue;
            try eps.append(alloc, try alloc.dupe(u8, piece));
        }
    } else {
        try eps.append(alloc, try alloc.dupe(u8, "127.0.0.1:2379"));
    }

    return eps.toOwnedSlice(alloc);
}

fn freeEndpoints(alloc: std.mem.Allocator, endpoints: [][]const u8) void {
    for (endpoints) |ep| alloc.free(ep);
    alloc.free(endpoints);
}

test "oracle pd smoke: build bundle and get timestamps" {
    const gpa = std.testing.allocator;

    const endpoints = try parseEndpoints(gpa);
    defer freeEndpoints(gpa, endpoints);

    // Build bundle (PDClient + PdOracle) with HTTP path for now
    var bundle = try oracle.build_pd_oracle(gpa, endpoints, false, false, 300);
    defer bundle.close();

    const o = bundle.oracle();

    // Global scope (default)
    var opt = oracle.Option.global();

    // getTimestamp
    const ts = try o.getTimestamp(gpa, &opt);
    std.debug.print("oracle ts={d}\n", .{ts});

    // getLowResolutionTimestamp should be available after setLastTS via getTimestamp
    const low = try o.getLowResolutionTimestamp(gpa, &opt);
    std.debug.print("oracle low-res ts={d}\n", .{low});

    // getTimestampAsync
    const fut = try o.getTimestampAsync(gpa, &opt);
    const ts_async = try fut.wait();
    std.debug.print("oracle ts_async={d}\n", .{ts_async});

    // Basic monotonicity checks (not strict across calls, but should be non-zero)
    try std.testing.expect(ts > 0);
    try std.testing.expect(ts_async >= ts);
}
