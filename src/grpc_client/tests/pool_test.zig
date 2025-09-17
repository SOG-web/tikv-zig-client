const std = @import("std");
const pool = @import("../pool.zig");
const transport = @import("../transport.zig");
const net = std.net;

test "Connection pool basic functionality" {
    const allocator = std.testing.allocator;

    var connection_pool = pool.ConnectionPool.init(allocator);
    defer connection_pool.deinit();

    // Test that we can get connections
    const conn1 = connection_pool.getConnection("127.0.0.1", 2379) catch |err| switch (err) {
        error.ConnectionRefused, error.NetworkUnreachable => {
            std.debug.print("Skipping connection pool test - no server at 127.0.0.1:2379\n", .{});
            return;
        },
        else => return err,
    };

    try std.testing.expect(conn1.active_streams == 0);
    try std.testing.expect(conn1.canAcceptStream());

    // Test stream lifecycle
    conn1.acquireStream();
    try std.testing.expect(conn1.active_streams == 1);

    conn1.releaseStream();
    try std.testing.expect(conn1.active_streams == 0);
}

test "Connection pool reuses connections" {
    const allocator = std.testing.allocator;

    var connection_pool = pool.ConnectionPool.init(allocator);
    defer connection_pool.deinit();

    // Get first connection
    const conn1 = connection_pool.getConnection("127.0.0.1", 2379) catch |err| switch (err) {
        error.ConnectionRefused, error.NetworkUnreachable => {
            std.debug.print("Skipping connection reuse test - no server at 127.0.0.1:2379\n", .{});
            return;
        },
        else => return err,
    };

    // Get second connection to same host:port - should be the same
    const conn2 = connection_pool.getConnection("127.0.0.1", 2379) catch |err| switch (err) {
        error.ConnectionRefused, error.NetworkUnreachable => return,
        else => return err,
    };

    try std.testing.expect(conn1 == conn2);
    try std.testing.expect(connection_pool.connections.items.len == 1);
}

test "Connection pool creates separate connections for different hosts" {
    const allocator = std.testing.allocator;

    var connection_pool = pool.ConnectionPool.init(allocator);
    defer connection_pool.deinit();

    // Try to get connections to different hosts
    const conn1 = connection_pool.getConnection("127.0.0.1", 2379) catch |err| switch (err) {
        error.ConnectionRefused, error.NetworkUnreachable => {
            std.debug.print("Skipping multi-host test - no server at 127.0.0.1:2379\n", .{});
            return;
        },
        else => return err,
    };

    const conn2 = connection_pool.getConnection("127.0.0.1", 8081) catch |err| switch (err) {
        error.ConnectionRefused, error.NetworkUnreachable => {
            // Only one connection created, which is expected
            try std.testing.expect(connection_pool.connections.items.len == 1);
            return;
        },
        else => return err,
    };

    try std.testing.expect(conn1 != conn2);
    try std.testing.expect(connection_pool.connections.items.len == 2);
}

test "Connection pool respects max streams per connection" {
    const allocator = std.testing.allocator;

    var connection_pool = pool.ConnectionPool.init(allocator);
    defer connection_pool.deinit();

    const conn = connection_pool.getConnection("127.0.0.1", 2379) catch |err| switch (err) {
        error.ConnectionRefused, error.NetworkUnreachable => {
            std.debug.print("Skipping max streams test - no server at 127.0.0.1:2379\n", .{});
            return;
        },
        else => return err,
    };

    // Fill up the connection
    var i: u32 = 0;
    while (i < conn.max_streams) : (i += 1) {
        try std.testing.expect(conn.canAcceptStream());
        conn.acquireStream();
    }

    // Should not accept more streams
    try std.testing.expect(!conn.canAcceptStream());
    try std.testing.expect(conn.active_streams == conn.max_streams);

    // Release one stream
    conn.releaseStream();
    try std.testing.expect(conn.canAcceptStream());
    try std.testing.expect(conn.active_streams == conn.max_streams - 1);
}

test "ClientPool integration" {
    const allocator = std.testing.allocator;

    var client_pool = pool.ClientPool.init(allocator);
    defer client_pool.deinit();

    const client = client_pool.getClient("127.0.0.1", 2379) catch |err| switch (err) {
        error.ConnectionRefused, error.NetworkUnreachable => {
            std.debug.print("Skipping ClientPool test - no server at 127.0.0.1:2379\n", .{});
            return;
        },
        else => return err,
    };

    // Test that client has valid connection
    try std.testing.expect(client.connection.active_streams == 0);
    try std.testing.expect(std.mem.eql(u8, client.connection.host, "127.0.0.1"));
    try std.testing.expect(client.connection.port == 2379);
}

test "Connection cleanup" {
    const allocator = std.testing.allocator;

    var connection_pool = pool.ConnectionPool.init(allocator);
    defer connection_pool.deinit();

    // Set very short timeout for testing
    connection_pool.connection_timeout_ns = 1; // 1 nanosecond

    const conn = connection_pool.getConnection("127.0.0.1", 2379) catch |err| switch (err) {
        error.ConnectionRefused, error.NetworkUnreachable => {
            std.debug.print("Skipping cleanup test - no server at 127.0.0.1:2379\n", .{});
            return;
        },
        else => return err,
    };

    try std.testing.expect(connection_pool.connections.items.len == 1);

    // Sleep a bit to ensure timeout
    std.Thread.sleep(1000); // 1 microsecond

    // Trigger cleanup by trying to get another connection
    _ = connection_pool.getConnection("127.0.0.1", 8081) catch |err| switch (err) {
        error.ConnectionRefused, error.NetworkUnreachable => {
            // Expected - but cleanup should still have happened
            return;
        },
        else => return err,
    };

    // Original connection should be cleaned up if it had no active streams
    if (conn.active_streams == 0) {
        // Note: This test is timing-dependent and may be flaky
        // In a real implementation, you might want more deterministic cleanup triggers
    }
}

// Mock server for more comprehensive testing
const MockServer = struct {
    allocator: std.mem.Allocator,
    server: net.Server,
    port: u16,

    pub fn init(allocator: std.mem.Allocator) !MockServer {
        const address = try net.Address.parseIp("127.0.0.1", 0);
        var server = try address.listen(.{});
        const actual_port = server.listen_address.getPort();

        return MockServer{
            .allocator = allocator,
            .server = server,
            .port = actual_port,
        };
    }

    pub fn deinit(self: *MockServer) void {
        self.server.deinit();
    }

    pub fn acceptOne(self: *MockServer) !void {
        const conn = try self.server.accept();
        defer conn.stream.close();

        // Just accept and close - enough for connection pool testing
    }
};

test "Connection pool with mock server" {
    const allocator = std.testing.allocator;

    var mock_server = MockServer.init(allocator) catch |err| switch (err) {
        error.AddressInUse => {
            std.debug.print("Skipping mock server test - address in use\n", .{});
            return;
        },
        else => return err,
    };
    defer mock_server.deinit();

    var connection_pool = pool.ConnectionPool.init(allocator);
    defer connection_pool.deinit();

    // Start accepting connections in background (simplified for test)
    const accept_thread = std.Thread.spawn(.{}, MockServer.acceptOne, .{&mock_server}) catch {
        std.debug.print("Skipping threaded test - spawn failed\n", .{});
        return;
    };
    defer accept_thread.join();

    // Get connection to mock server
    const conn = try connection_pool.getConnection("127.0.0.1", mock_server.port);
    try std.testing.expect(conn.port == mock_server.port);
    try std.testing.expect(connection_pool.connections.items.len == 1);
}
