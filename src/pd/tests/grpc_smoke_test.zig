const std = @import("std");
const grpc = @import("../../grpc_client/mod.zig");
const pdpb = @import("kvproto").pdpb;

fn parseHostPort(allocator: std.mem.Allocator, addr: []const u8) !struct { host: []const u8, port: u16 } {
    if (std.mem.lastIndexOfScalar(u8, addr, ':')) |i| {
        const host = try allocator.dupe(u8, addr[0..i]);
        const port_s = addr[i + 1 ..];
        const port = try std.fmt.parseInt(u16, port_s, 10);
        return .{ .host = host, .port = port };
    }
    return error.InvalidAddress;
}

fn freeMembers(alloc: std.mem.Allocator, resp: *pdpb.GetMembersResponse) void {
    // Free slices in response according to pb helpers
    resp.deinit(alloc);
}

test "pd grpc smoke: GetMembers" {
    const gpa = std.testing.allocator;

    // Always run this PD gRPC smoke test (no gates)

    var endpoints = std.ArrayList([]const u8){};
    defer endpoints.deinit(gpa);

    try endpoints.append(gpa, "127.0.0.1:2379");

    // Use first endpoint
    const ep = endpoints.items[0];
    const hp = try parseHostPort(gpa, ep);
    defer gpa.free(hp.host);

    // Create GrpcClient (plaintext for now)
    var client = try grpc.GrpcClient.init(gpa, hp.host, hp.port);
    defer client.deinit();

    std.debug.print("PD gRPC call: {any}\n", .{ep});

    // Build empty GetMembersRequest
    var req = pdpb.GetMembersRequest{};

    var aw: std.Io.Writer.Allocating = std.Io.Writer.Allocating.init(gpa);
    defer aw.deinit();
    try req.encode(&aw.writer, gpa);
    const req_bytes = aw.written();

    std.debug.print("PD gRPC request: {s}\n", .{req_bytes});

    // Call PD.GetMembers
    const resp_bytes = client.call("/pdpb.PD/GetMembers", req_bytes, .gzip, 5000) catch |err| {
        std.debug.print("PD gRPC call failed: {any}\n", .{err});
        return;
    };

    std.debug.print("PD gRPC response: {s}\n", .{resp_bytes});
    defer gpa.free(resp_bytes);

    // Decode response
    var reader = std.Io.Reader.fixed(resp_bytes);
    var resp = pdpb.GetMembersResponse.decode(&reader, gpa) catch |err| {
        std.debug.print("Decode GetMembersResponse failed: {}\n", .{err});
        return;
    };
    defer freeMembers(gpa, &resp);

    std.debug.print("PD members: {any}\n", .{resp});
}
