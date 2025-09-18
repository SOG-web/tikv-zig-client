const std = @import("std");
const client_mod = @import("client.zig");
const transport_mod = @import("transport.zig");
const http2 = @import("http2/connection.zig");
const compression = @import("features/compression.zig");

const PooledConnection = struct {
    transport: *transport_mod.Transport,
    host: []u8, // owned
    port: u16,
    active_streams: u32,
    max_streams: u32,
    last_used: i128, // nanoseconds

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16, transport: *transport_mod.Transport) !PooledConnection {
        return PooledConnection{
            .transport = transport,
            .host = try allocator.dupe(u8, host),
            .port = port,
            .active_streams = 0,
            .max_streams = 100, // HTTP/2 default concurrent streams
            .last_used = std.time.nanoTimestamp(),
        };
    }

    pub fn deinit(self: *PooledConnection, allocator: std.mem.Allocator) void {
        allocator.free(self.host);
        self.transport.deinit();
        allocator.destroy(self.transport);
    }

    pub fn canAcceptStream(self: *PooledConnection) bool {
        return self.active_streams < self.max_streams;
    }

    pub fn acquireStream(self: *PooledConnection) void {
        self.active_streams += 1;
        self.last_used = std.time.nanoTimestamp();
    }

    pub fn releaseStream(self: *PooledConnection) void {
        if (self.active_streams > 0) {
            self.active_streams -= 1;
        }
    }
};

pub const ConnectionPool = struct {
    allocator: std.mem.Allocator,
    connections: std.ArrayList(PooledConnection),
    max_connections_per_host: u32,
    connection_timeout_ns: i128,

    pub fn init(allocator: std.mem.Allocator) ConnectionPool {
        return .{
            .allocator = allocator,
            .connections = std.ArrayList(PooledConnection){},
            .max_connections_per_host = 10,
            .connection_timeout_ns = 300 * std.time.ns_per_s, // 5 minutes
        };
    }

    pub fn deinit(self: *ConnectionPool) void {
        for (self.connections.items) |*conn| {
            conn.deinit(self.allocator);
        }
        self.connections.deinit(self.allocator);
    }

    pub fn getConnection(self: *ConnectionPool, host: []const u8, port: u16) !*PooledConnection {
        // Clean up expired connections first
        try self.cleanupExpiredConnections();

        // Look for existing connection that can accept more streams
        for (self.connections.items) |*conn| {
            if (std.mem.eql(u8, conn.host, host) and conn.port == port and conn.canAcceptStream()) {
                return conn;
            }
        }

        // Check if we can create a new connection for this host
        const host_connections = self.countConnectionsForHost(host, port);
        if (host_connections >= self.max_connections_per_host) {
            // Find least loaded connection for this host
            return self.getLeastLoadedConnection(host, port) orelse error.TooManyConnections;
        }

        // Create new connection
        return try self.createConnection(host, port);
    }

    fn createConnection(self: *ConnectionPool, host: []const u8, port: u16) !*PooledConnection {
        const stream = try std.net.tcpConnectToHost(self.allocator, host, port);
        const transport = try self.allocator.create(transport_mod.Transport);
        transport.* = try transport_mod.Transport.init(self.allocator, stream);

        const conn = try PooledConnection.init(self.allocator, host, port, transport);
        try self.connections.append(self.allocator, conn);

        return &self.connections.items[self.connections.items.len - 1];
    }

    fn countConnectionsForHost(self: *ConnectionPool, host: []const u8, port: u16) u32 {
        var count: u32 = 0;
        for (self.connections.items) |*conn| {
            if (std.mem.eql(u8, conn.host, host) and conn.port == port) {
                count += 1;
            }
        }
        return count;
    }

    fn getLeastLoadedConnection(self: *ConnectionPool, host: []const u8, port: u16) ?*PooledConnection {
        var best: ?*PooledConnection = null;
        var min_streams: u32 = std.math.maxInt(u32);

        for (self.connections.items) |*conn| {
            if (std.mem.eql(u8, conn.host, host) and conn.port == port and conn.active_streams < min_streams) {
                best = conn;
                min_streams = conn.active_streams;
            }
        }

        return best;
    }

    fn cleanupExpiredConnections(self: *ConnectionPool) !void {
        const now = std.time.nanoTimestamp();
        var i: usize = 0;

        while (i < self.connections.items.len) {
            const conn = &self.connections.items[i];
            if (conn.active_streams == 0 and (now - conn.last_used) > self.connection_timeout_ns) {
                conn.deinit(self.allocator);
                _ = self.connections.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }
};

// Enhanced client pool that uses connection pooling
pub const ClientPool = struct {
    allocator: std.mem.Allocator,
    connection_pool: ConnectionPool,

    pub fn init(allocator: std.mem.Allocator) ClientPool {
        return .{
            .allocator = allocator,
            .connection_pool = ConnectionPool.init(allocator),
        };
    }

    pub fn deinit(self: *ClientPool) void {
        self.connection_pool.deinit();
    }

    // Get a multiplexed client that shares connections
    pub fn getClient(self: *ClientPool, host: []const u8, port: u16) !MultiplexedClient {
        const conn = try self.connection_pool.getConnection(host, port);
        return MultiplexedClient{
            .connection = conn,
            .pool = self,
        };
    }
};

// Wrapper that manages stream lifecycle on a pooled connection
pub const MultiplexedClient = struct {
    connection: *PooledConnection,
    pool: *ClientPool,

    pub fn call(
        self: *MultiplexedClient,
        path: []const u8,
        request: []const u8,
        compression_alg: compression.Compression.Algorithm,
        timeout_ms: ?u64,
    ) ![]u8 {
        self.connection.acquireStream();
        defer self.connection.releaseStream();

        // Use the pooled transport for the actual call
        const authority = try std.fmt.allocPrint(self.pool.allocator, "{s}:{d}", .{ self.connection.host, self.connection.port });
        defer self.pool.allocator.free(authority);

        return try self.connection.transport.unary(authority, path, request, compression_alg, null, timeout_ms);
    }
};
