const std = @import("std");
const grpc = @import("../grpc_client/mod.zig");
const grpc_pool = @import("../grpc_client/pool.zig");

const ClientRef = union(enum) { owned: grpc.GrpcClient, pooled: *grpc.GrpcClient };

pub const StreamHandle = opaque {}; // reserved for future streaming

pub const Transport = struct {
    allocator: std.mem.Allocator,
    client: ClientRef,

    pub fn init(allocator: std.mem.Allocator, addr: []const u8) !Transport {
        const hp = try parseHostPort(allocator, addr);
        defer allocator.free(hp.host);
        const client = try grpc.GrpcClient.init(allocator, hp.host, hp.port);
        return .{ .allocator = allocator, .client = .{ .owned = client } };
    }

    pub fn initWithPool(allocator: std.mem.Allocator, addr: []const u8, pool: *grpc_pool.ClientPool) !Transport {
        const hp = try parseHostPort(allocator, addr);
        defer allocator.free(hp.host);
        const cli_ptr = try pool.get(hp.host, hp.port);
        return .{ .allocator = allocator, .client = .{ .pooled = cli_ptr } };
    }

    pub fn deinit(self: *Transport) void {
        switch (self.client) {
            .owned => |*c| c.deinit(),
            .pooled => |_| {}, // pool owns lifecycle
        }
    }

    pub fn unary(self: *Transport, path: []const u8, body: []const u8, alg: grpc.features.compression.Compression.Algorithm, timeout_ms: ?u64) ![]u8 {
        const cli_ptr: *grpc.GrpcClient = switch (self.client) {
            .owned => |*c| c,
            .pooled => |c| c,
        };
        return try cli_ptr.call(path, body, alg, timeout_ms);
    }

    pub fn takeLastGrpcStatus(self: *Transport) ?grpc.GrpcStatusInfo {
        const cli_ptr: *grpc.GrpcClient = switch (self.client) {
            .owned => |*c| c,
            .pooled => |c| c,
        };
        return cli_ptr.takeLastGrpcStatus();
    }
};

const HostPort = struct { host: []const u8, port: u16 };

fn parseHostPort(allocator: std.mem.Allocator, addr: []const u8) !HostPort {
    // Very simple IPv4 host:port parser; TODO: IPv6 bracket form
    if (std.mem.lastIndexOfScalar(u8, addr, ':')) |i| {
        const host = try allocator.dupe(u8, addr[0..i]);
        const port_s = addr[i + 1 ..];
        const port = try std.fmt.parseInt(u16, port_s, 10);
        return .{ .host = host, .port = port };
    }
    return error.InvalidAddress;
}
