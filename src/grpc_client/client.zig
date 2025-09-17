const std = @import("std");
// const proto = @import("proto/service.zig");
const transport = @import("transport.zig");
const compression = @import("features/compression.zig");
const auth = @import("features/auth.zig");
const streaming = @import("features/streaming.zig");
const health = @import("features/health.zig");

pub const GrpcClient = struct {
    allocator: std.mem.Allocator,
    transport: transport.Transport,
    compression: compression.Compression,
    auth: ?auth.Auth,
    authority: []const u8,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) !GrpcClient {
        const address = try std.net.Address.parseIp(host, port);
        const connection = try std.net.tcpConnectToAddress(address);
        const authority = try std.fmt.allocPrint(allocator, "{s}:{d}", .{ host, port });

        return GrpcClient{
            .allocator = allocator,
            .transport = try transport.Transport.init(allocator, connection),
            .compression = compression.Compression.init(allocator),
            .auth = null,
            .authority = authority,
        };
    }

    pub fn deinit(self: *GrpcClient) void {
        self.transport.deinit();
        self.allocator.free(self.authority);
    }

    pub fn setAuth(self: *GrpcClient, secret_key: []const u8) !void {
        self.auth = auth.Auth.init(self.allocator, secret_key);
    }

    pub fn checkHealth(self: *GrpcClient, service: []const u8) !health.HealthStatus {
        const request = try std.json.stringify(.{
            .service = service,
        }, .{}, self.allocator);
        defer self.allocator.free(request);

        const response = try self.call("Check", request, .none, null);
        defer self.allocator.free(response);

        const parsed = try std.json.parse(struct {
            status: health.HealthStatus,
        }, .{ .allocator = self.allocator }, response);
        defer std.json.parseFree(parsed, .{ .allocator = self.allocator });

        return parsed.status;
    }

    pub fn call(self: *GrpcClient, method: []const u8, request: []const u8, compression_alg: compression.Compression.Algorithm, timeout_ms: ?u64) ![]u8 {
        // Prepare optional auth token
        var token_opt: ?[]const u8 = null;
        if (self.auth) |*auth_client| {
            std.debug.print("Generating auth token\n", .{});
            token_opt = try auth_client.generateToken("client", 3600);
        }
        defer if (token_opt) |t| self.allocator.free(t);
        std.debug.print("Auth token: {any}\n", .{token_opt});
        // Ensure path starts with '/'
        var path_owned: ?[]const u8 = null;
        const path: []const u8 = blk: {
            if (method.len > 0 and method[0] == '/') break :blk method;
            const p = try std.mem.concat(self.allocator, u8, &.{ "/", method });
            path_owned = p;
            break :blk p;
        };
        defer if (path_owned) |p| self.allocator.free(p);
        std.debug.print("Path: {s}\n", .{path});

        // Call unary transport (transport will frame and optionally compress per gRPC rules)
        return try self.transport.unary(self.authority, path, request, compression_alg, token_opt, timeout_ms);
    }

    pub fn takeLastGrpcStatus(self: *GrpcClient) ?transport.GrpcStatusInfo {
        return self.transport.takeLastGrpcStatus();
    }
};
