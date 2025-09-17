const std = @import("std");
const request_mod = @import("request.zig");

const Request = request_mod.Request;

pub const RequestBatch = struct {
    alloc: std.mem.Allocator,
    items: std.ArrayList(Request),

    pub fn init(allocator: std.mem.Allocator) RequestBatch {
        return .{ .alloc = allocator, .items = std.ArrayList(Request){} };
    }

    pub fn deinit(self: *RequestBatch) void {
        self.items.deinit(self.alloc);
    }

    pub fn append(self: *RequestBatch, req: Request) !void {
        try self.items.append(self.alloc, req);
    }

    pub fn len(self: *RequestBatch) usize {
        return self.items.items.len;
    }

    pub fn clear(self: *RequestBatch) void {
        self.items.clearRetainingCapacity();
    }
};

test "RequestBatch basic" {
    var rb = RequestBatch.init(std.testing.allocator);
    defer rb.deinit();
    try std.testing.expectEqual(@as(usize, 0), rb.len());
}
