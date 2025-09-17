const std = @import("std");
const request_mod = @import("request.zig");
const call_mod = @import("call.zig");

const Request = request_mod.Request;
const RequestType = request_mod.RequestType;
const CallResult = call_mod.CallResult;

// Send function signature with explicit context pointer to allow endpoint instance passing.
pub const SendCtxFn = fn (ctx: *anyopaque, target: []const u8, req: *Request) anyerror!CallResult;

// Interceptor with explicit before/after hooks. The onion model is implemented by Chain.aroundCtx
// which invokes all before hooks in registration order and after hooks in reverse order.
pub const Interceptor = struct {
    beforeSend: fn (self: *const Interceptor, target: []const u8, req: *Request) void = defaultBefore,
    afterRecv: fn (self: *const Interceptor, target: []const u8, req: *const Request, result: *const CallResult) void = defaultAfter,

    pub fn defaultBefore(_: *const Interceptor, _: []const u8, _: *Request) void {}
    pub fn defaultAfter(_: *const Interceptor, _: []const u8, _: *const Request, _: *const CallResult) void {}
};

pub const NoopInterceptor = Interceptor{};

pub const Chain = struct {
    alloc: std.mem.Allocator,
    list: std.ArrayList(*const Interceptor),

    pub fn init(alloc: std.mem.Allocator) Chain {
        return .{ .alloc = alloc, .list = std.ArrayList(*const Interceptor).init(alloc) };
    }
    pub fn deinit(self: *Chain) void {
        self.list.deinit();
    }
    pub fn link(self: *Chain, ic: *const Interceptor) *Chain {
        self.list.append(ic) catch {};
        return self;
    }

    // Run the chain around the provided send function.
    pub fn aroundCtx(self: *const Chain, ctx: *anyopaque, target: []const u8, req: *Request, send: SendCtxFn) anyerror!CallResult {
        // TODO: Note: we currently intercept around CallResult since the transport is stubbed.
        // When we wire real RPCs and tikvrpc.Response return values, we can extend afterRecv to accept
        // richer response info (or add another chain specialized for response types).
        // before in registration order
        for (self.list.items) |ic| ic.beforeSend(ic, target, req);
        // perform send
        var result = try send(ctx, target, req);
        // after in reverse order
        var i: isize = @as(isize, @intCast(self.list.items.len)) - 1;
        while (i >= 0) : (i -= 1) {
            const ic = self.list.items[@as(usize, @intCast(i))];
            ic.afterRecv(ic, target, req, &result);
        }
        return result;
    }
};

test "interceptor chain pre/post order" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = struct {
        fn before(_: *const Interceptor, _: []const u8, _: *Request) void {}
        fn after(_: *const Interceptor, _: []const u8, _: *const Request, _: *const CallResult) void {}
    };
    var a = Interceptor{ .beforeSend = A.before, .afterRecv = A.after };
    var chain = Chain.init(gpa.allocator());
    defer chain.deinit();
    _ = chain.link(&a);
}
