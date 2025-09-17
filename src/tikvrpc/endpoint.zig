const std = @import("std");
const request_mod = @import("request.zig");
const call_mod = @import("call.zig");
const transport = @import("transport.zig");
const kvproto = @import("kvproto");
const metapb = kvproto.metapb;
const interceptor = @import("interceptor.zig");

const Request = request_mod.Request;
const RequestType = request_mod.RequestType;
const CallResult = call_mod.CallResult;
const CopStreamResponse = request_mod.CopStreamResponse;
const BatchCopStreamResponse = request_mod.BatchCopStreamResponse;
const MPPStreamResponse = request_mod.MPPStreamResponse;

pub const EndpointError = error{ NotImplemented, Network, Canceled };

pub const Endpoint = struct {
    addr: []const u8,
    trans: ?*transport.Transport = null,
    chain: ?*interceptor.Chain = null,

    pub fn init(addr: []const u8) Endpoint {
        return .{ .addr = addr, .trans = null, .chain = null };
    }

    pub fn initWithTransport(addr: []const u8, trans: *transport.Transport) Endpoint {
        return .{ .addr = addr, .trans = trans, .chain = null };
    }

    pub fn setInterceptorChain(self: *Endpoint, chain: *interceptor.Chain) void {
        self.chain = chain;
    }

    /// Stub call - in future will perform real RPC. For now measures elapsed time.
    pub fn call(self: *Endpoint, req: Request) EndpointError!CallResult {
        var tmp = req;
        return self.callCtx(&tmp, null, null);
    }

    /// Same as call, but automatically sets kvrpc Context using provided region/peer.
    pub fn callCtx(self: *Endpoint, req: *Request, region: ?*const metapb.Region, peer: ?*const metapb.Peer) EndpointError!CallResult {
        if (self.chain) |ch| {
            const SendWrap = struct {
                fn send(ctx: *anyopaque, target: []const u8, reqp: *request_mod.Request) anyerror!CallResult {
                    var ep: *Endpoint = @ptrCast(@alignCast(ctx));
                    return ep.doCall(reqp, target, null, null, region, peer);
                }
            };
            return ch.aroundCtx(@ptrCast(self), self.addr, req, SendWrap.send) catch |e| switch (e) {
                else => return EndpointError.NotImplemented, // map anyerror to EndpointError in stub
            };
        }
        return self.doCall(req, self.addr, null, null, region, peer);
    }

    fn doCall(self: *Endpoint, req: *Request, target: []const u8, _unused1: ?*anyopaque, _unused2: ?*anyopaque, region: ?*const metapb.Region, peer: ?*const metapb.Peer) EndpointError!CallResult {
        _ = self; _ = target; _ = _unused1; _ = _unused2;
        request_mod.setContext(req, region, peer);
        const start = std.time.nanoTimestamp();
        var cr = CallResult.start(req.typ);
        cr.finish(start);
        return cr;
    }

    /// Stubbed stream openers — populate shape without real network
    pub fn openCopStream(self: *Endpoint, req: Request) EndpointError!CopStreamResponse {
        var tmp = req;
        return self.openCopStreamCtx(&tmp, null, null);
    }

    pub fn openCopStreamCtx(self: *Endpoint, req: *Request, region: ?*const metapb.Region, peer: ?*const metapb.Peer) EndpointError!CopStreamResponse {
        request_mod.setContext(req, region, peer);
        _ = self;
        return .{ .stream = null, .first = null, .timeout_ns = 0, .lease = .{} };
    }

    pub fn openBatchCopStream(self: *Endpoint, req: Request) EndpointError!BatchCopStreamResponse {
        var tmp = req;
        return self.openBatchCopStreamCtx(&tmp, null, null);
    }

    pub fn openBatchCopStreamCtx(self: *Endpoint, req: *Request, region: ?*const metapb.Region, peer: ?*const metapb.Peer) EndpointError!BatchCopStreamResponse {
        request_mod.setContext(req, region, peer);
        _ = self;
        return .{ .stream = null, .first = null, .timeout_ns = 0, .lease = .{} };
    }

    pub fn openMPPStream(self: *Endpoint, req: Request) EndpointError!MPPStreamResponse {
        var tmp = req;
        return self.openMPPStreamCtx(&tmp, null, null);
    }

    pub fn openMPPStreamCtx(self: *Endpoint, req: *Request, region: ?*const metapb.Region, peer: ?*const metapb.Peer) EndpointError!MPPStreamResponse {
        request_mod.setContext(req, region, peer);
        _ = self;
        return .{ .stream = null, .first = null, .timeout_ns = 0, .lease = .{} };
    }
};

test "endpoint call stub works" {
    const ep = Endpoint.init("127.0.0.1:20160");
    _ = ep;
}
