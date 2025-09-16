// TikvRPC interceptor (skeleton)
// Mirrors the concept from client-go/tikvrpc/interceptor.
// NOTE: This is an API placeholder; we will flesh out composition once
// Request/Response call sites are ported.
const std = @import("std");

/// Opaque request/response placeholders to avoid tight coupling at this stage.
pub const Request = opaque {};
pub const Response = opaque {};

/// Function that initiates an RPC to a target with a request and returns a response.
/// Error set is left open for now.
pub const RPCInterceptorFunc = *const fn (target: []const u8, req: *Request) anyerror!*Response;

/// RPCInterceptor decorates a next function and returns a new callable.
pub const RPCInterceptor = *const fn (next: RPCInterceptorFunc) RPCInterceptorFunc;

/// A simple chain holder. Build returns a struct that can execute the chain
/// given a base function pointer.
pub const RPCInterceptorChain = struct {
    alloc: std.mem.Allocator,
    list: std.ArrayList(RPCInterceptor),

    pub fn init(alloc: std.mem.Allocator) RPCInterceptorChain {
        return .{ .alloc = alloc, .list = std.ArrayList(RPCInterceptor).init(alloc) };
    }
    pub fn deinit(self: *RPCInterceptorChain) void { self.list.deinit(); }

    pub fn link(self: *RPCInterceptorChain, it: RPCInterceptor) !void {
        try self.list.append(it);
    }

    pub const Built = struct {
        chain: []const RPCInterceptor,
        pub fn call(self: Built, base: RPCInterceptorFunc, target: []const u8, req: *Request) anyerror!*Response {
            var next = base;
            var i: usize = self.chain.len;
            while (i > 0) {
                i -= 1;
                next = self.chain[i](next);
            }
            return next(target, req);
        }
    };

    pub fn build(self: *const RPCInterceptorChain) Built {
        return .{ .chain = self.list.items };
    }
};

test {
    std.testing.refAllDecls(@This());
}
