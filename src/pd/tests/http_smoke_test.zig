const std = @import("std");
const pd = @import("../mod.zig");

fn freeRegions(alloc: std.mem.Allocator, regs: []pd.Region) void {
    for (regs) |r| {
        alloc.free(r.start_key);
        alloc.free(r.end_key);
    }
    alloc.free(regs);
}

test "pd http smoke: getAllStores, getRegion, getRegionByID, scanRegions" {
    const gpa = std.testing.allocator;

    // Endpoint source: env PD_ENDPOINT (comma-separated) or default 127.0.0.1:2379
    const ep_env = std.process.getEnvVarOwned(gpa, "PD_ENDPOINT") catch |e| switch (e) {
        error.EnvironmentVariableNotFound => null,
        else => return e,
    };
    defer if (ep_env) |s| gpa.free(s);

    var eps = std.ArrayList([]const u8){};
    defer eps.deinit(gpa);

    if (ep_env) |s| {
        // Split by comma
        var it = std.mem.splitScalar(u8, s, ',');
        while (it.next()) |piece| {
            if (piece.len == 0) continue;
            try eps.append(gpa, try gpa.dupe(u8, piece));
        }
    } else {
        try eps.append(gpa, "127.0.0.1:2379");
    }

    const endpoints: [][]const u8 = eps.items;

    // Prefer HTTP for now; user can flip prefer_grpc=true once gRPC-zig is wired.
    var client = try pd.PDClientFactory.grpc_with_transport_options(gpa, endpoints, false, false);
    defer client.close();

    // getAllStores
    const stores = try client.getAllStores();
    defer {
        for (stores) |s| gpa.free(s.address);
        gpa.free(stores);
    }
    std.debug.print("stores={d}\n", .{stores.len});

    // getStore for the first store (if present)
    if (stores.len > 0) {
        const s1 = try client.getStore(stores[0].id);
        defer gpa.free(s1.address);
        std.debug.print("store id={d} addr={s}\n", .{ s1.id, s1.address });
    }

    // getRegion by empty key (may return first region or error depending on cluster)
    var have_region = false;
    const region_or_err = client.getRegion("", false);
    if (region_or_err) |r| {
        defer {
            gpa.free(r.start_key);
            gpa.free(r.end_key);
        }
        std.debug.print("region id={d} start={s} end={s}\n", .{ r.id, r.start_key, r.end_key });
        have_region = true;
        // getRegionByID
        const r2 = try client.getRegionByID(r.id, false);
        defer {
            gpa.free(r2.start_key);
            gpa.free(r2.end_key);
        }
        std.debug.print("regionByID id={d} start={s} end={s}\n", .{ r2.id, r2.start_key, r2.end_key });
    } else |_| {
        std.debug.print("getRegion(\"\") failed; continuing with scanRegions only\n", .{});
    }

    // scanRegions over a small range
    const regs = try client.scanRegions("", "\xff", 8, false);
    defer freeRegions(gpa, regs);
    std.debug.print("scanRegions returned {d} regions\n", .{regs.len});

    // If getRegion failed, still exercise getRegionByID using one from scan
    if (!have_region and regs.len > 0) {
        const r3 = try client.getRegionByID(regs[0].id, false);
        defer {
            gpa.free(r3.start_key);
            gpa.free(r3.end_key);
        }
        std.debug.print("regionByID-from-scan id={d} start={s} end={s}\n", .{ r3.id, r3.start_key, r3.end_key });
    }
}
