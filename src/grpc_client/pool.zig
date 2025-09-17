const std = @import("std");
const client_mod = @import("client.zig");

pub const ClientPool = struct {
    allocator: std.mem.Allocator,
    map: std.StringHashMap(*client_mod.GrpcClient),

    pub fn init(allocator: std.mem.Allocator) ClientPool {
        return .{ .allocator = allocator, .map = std.StringHashMap(*client_mod.GrpcClient).init(allocator) };
    }

    pub fn deinit(self: *ClientPool) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const cli = entry.value_ptr.*;
            if (cli) |c| {
                c.deinit();
                self.allocator.destroy(c);
            }
            self.allocator.free(key);
        }
        self.map.deinit();
    }

    pub fn get(self: *ClientPool, host: []const u8, port: u16) !*client_mod.GrpcClient {
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{d}", .{ host, port });
        if (self.map.get(key)) |cli_ptr| {
            // key is owned by pool; free temporary key
            self.allocator.free(key);
            return cli_ptr;
        }
        const cli = try self.allocator.create(client_mod.GrpcClient);
        cli.* = try client_mod.GrpcClient.init(self.allocator, host, port);
        // store under owned key
        try self.map.put(key, cli);
        return cli;
    }
};
