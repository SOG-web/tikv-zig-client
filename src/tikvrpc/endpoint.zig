const std = @import("std");
const request_mod = @import("request.zig");
const call_mod = @import("call.zig");
const transport = @import("transport.zig");
const grpc = @import("../grpc_client/mod.zig");
const kvproto = @import("kvproto");
const metapb = kvproto.metapb;
const kvrpcpb = kvproto.kvrpcpb;
const interceptor = @import("interceptor.zig");

const Request = request_mod.Request;
const RequestType = request_mod.RequestType;
const CallResult = call_mod.CallResult;
const CopStreamResponse = request_mod.CopStreamResponse;
const BatchCopStreamResponse = request_mod.BatchCopStreamResponse;
const MPPStreamResponse = request_mod.MPPStreamResponse;

pub const EndpointError = error{
    NotImplemented,
    Network,
    Canceled,
    Timeout,
    InvalidHeader,
    GrpcStatus,
    RegionError,
    KeyError,
};

pub const Endpoint = struct {
    addr: []const u8,
    trans: ?*transport.Transport = null,
    chain: ?*interceptor.Chain = null,
    last_kv_error: ?[]u8 = null, // owned error description captured from last decode
    last_grpc_status: ?grpc.GrpcStatusInfo = null,

    pub fn init(addr: []const u8) Endpoint {
        return .{ .addr = addr, .trans = null, .chain = null };
    }

    pub fn initWithTransport(addr: []const u8, trans: *transport.Transport) Endpoint {
        return .{ .addr = addr, .trans = trans, .chain = null };
    }

    pub fn setInterceptorChain(self: *Endpoint, chain: *interceptor.Chain) void {
        self.chain = chain;
    }

    pub fn deinit(self: *Endpoint) void {
        if (self.last_kv_error) |m| std.heap.page_allocator.free(m);
        if (self.last_grpc_status) |st| std.heap.page_allocator.free(st.message);
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
        _ = target;
        _ = _unused1;
        _ = _unused2;
        request_mod.setContext(req, region, peer);

        const trans = self.trans orelse return EndpointError.NotImplemented;

        // Map request type to gRPC method path and encode request
        const path = methodPath(req.typ) orelse return EndpointError.NotImplemented;

        // Encode protobuf request to bytes using Allocating writer
        var aw: std.Io.Writer.Allocating = std.Io.Writer.Allocating.init(std.heap.page_allocator);
        defer aw.deinit();

        switch (req.payload) {
            .Get => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .Scan => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .Prewrite => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .Commit => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .Cleanup => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .BatchGet => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .BatchRollback => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .ScanLock => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .ResolveLock => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .GC => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .DeleteRange => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .RawGet => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .RawBatchGet => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .RawPut => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .RawBatchPut => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .RawDelete => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .RawBatchDelete => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .RawScan => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .RawDeleteRange => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .Coprocessor => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .PessimisticLock => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .PessimisticRollback => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .CheckTxnStatus => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .TxnHeartBeat => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .CheckSecondaryLocks => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .RawCoprocessor => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .StoreSafeTS => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .LockWaitInfo => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .MPPTask => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .MPPConn => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .MPPCancel => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .MPPAlive => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .MvccGetByKey => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .MvccGetByStartTs => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .SplitRegion => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .DebugGetRegionProperties => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .ReadIndex => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .CheckLeader => |m| try m.encode(&aw.writer, std.heap.page_allocator),
            .Empty => |_| {},
            else => return EndpointError.NotImplemented,
        }

        const req_bytes = aw.written();

        const start = std.time.nanoTimestamp();
        // Send unary with per-call compression option
        const alg = mapCompression(req.opts.compression_alg);
        const resp_bytes = trans.unary(path, req_bytes, alg, req.opts.timeout_ms) catch |e| switch (e) {
            grpc.TransportError.GrpcStatus => {
                if (trans.takeLastGrpcStatus()) |st| {
                    if (self.last_grpc_status) |old| std.heap.page_allocator.free(old.message);
                    self.last_grpc_status = .{ .code = st.code, .message = st.message };
                }
                return EndpointError.GrpcStatus;
            },
            grpc.TransportError.Timeout => return EndpointError.Timeout,
            grpc.TransportError.InvalidHeader => return EndpointError.InvalidHeader,
            else => return EndpointError.Network,
        };
        defer std.heap.page_allocator.free(resp_bytes);

        // Decode response and surface region/key errors
        try self.decodeResponseForType(req.typ, resp_bytes);

        var cr = CallResult.start(req.typ);
        cr.finish(start);
        return cr;
    }

    fn mapCompression(c: request_mod.Compression) grpc.features.compression.Compression.Algorithm {
        return switch (c) {
            .none => .none,
            .gzip => .gzip,
            .deflate => .deflate,
        };
    }

    fn methodPath(t: RequestType) ?[]const u8 {
        return switch (t) {
            .Get => "/tikvpb.Tikv/KvGet",
            .Scan => "/tikvpb.Tikv/KvScan",
            .Prewrite => "/tikvpb.Tikv/KvPrewrite",
            .PessimisticLock => "/tikvpb.Tikv/KvPessimisticLock",
            .PessimisticRollback => "/tikvpb.Tikv/KVPessimisticRollback",
            .TxnHeartBeat => "/tikvpb.Tikv/KvTxnHeartBeat",
            .CheckTxnStatus => "/tikvpb.Tikv/KvCheckTxnStatus",
            .CheckSecondaryLocks => "/tikvpb.Tikv/KvCheckSecondaryLocks",
            .Commit => "/tikvpb.Tikv/KvCommit",
            .Import => "/tikvpb.Tikv/KvImport",
            .Cleanup => "/tikvpb.Tikv/KvCleanup",
            .BatchGet => "/tikvpb.Tikv/KvBatchGet",
            .BatchRollback => "/tikvpb.Tikv/KvBatchRollback",
            .ScanLock => "/tikvpb.Tikv/KvScanLock",
            .ResolveLock => "/tikvpb.Tikv/KvResolveLock",
            .GC => "/tikvpb.Tikv/KvGC",
            .DeleteRange => "/tikvpb.Tikv/KvDeleteRange",
            .RawGet => "/tikvpb.Tikv/RawGet",
            .RawBatchGet => "/tikvpb.Tikv/RawBatchGet",
            .RawPut => "/tikvpb.Tikv/RawPut",
            .RawBatchPut => "/tikvpb.Tikv/RawBatchPut",
            .RawDelete => "/tikvpb.Tikv/RawDelete",
            .RawBatchDelete => "/tikvpb.Tikv/RawBatchDelete",
            .RawScan => "/tikvpb.Tikv/RawScan",
            .RawDeleteRange => "/tikvpb.Tikv/RawDeleteRange",
            .RawBatchScan => "/tikvpb.Tikv/RawBatchScan",
            .RawCoprocessor => "/tikvpb.Tikv/RawCoprocessor",
            .Coprocessor => "/tikvpb.Tikv/Coprocessor",
            //TODO: check to confirm if this has been implemented - they are correct/valid endpoints
            .RawGetKeyTTL => "/tikvpb.Tikv/RawGetKeyTTL",
            .RawCompareAndSwap => "/tikvpb.Tikv/RawCompareAndSwap",
            .RawChecksum => "/tikvpb.Tikv/RawChecksum",
            .UnsafeDestroyRange => "/tikvpb.Tikv/UnsafeDestroyRange",
            .RegisterLockObserver => "/tikvpb.Tikv/RegisterLockObserver",
            .CheckLockObserver => "/tikvpb.Tikv/CheckLockObserver",
            .RemoveLockObserver => "/tikvpb.Tikv/RemoveLockObserver",
            .PhysicalScanLock => "/tikvpb.Tikv/PhysicalScanLock",
            .CoprocessorStream => "/tikvpb.Tikv/CoprocessorStream",
            .BatchCop => "/tikvpb.Tikv/BatchCoprocessor",
            .StoreSafeTS => "/tikvpb.Tikv/GetStoreSafeTS",
            .LockWaitInfo => "/tikvpb.Tikv/GetLockWaitInfo",
            .MPPTask => "/tikvpb.Tikv/DispatchMPPTask",
            .MPPConn => "/tikvpb.Tikv/EstablishMPPConnection",
            .MPPCancel => "/tikvpb.Tikv/CancelMPPTask",
            .MPPAlive => "/tikvpb.Tikv/IsAlive",
            .MvccGetByKey => "/tikvpb.Tikv/MvccGetByKey",
            .MvccGetByStartTs => "/tikvpb.Tikv/MvccGetByStartTs",
            .SplitRegion => "/tikvpb.Tikv/SplitRegion",
            .DebugGetRegionProperties => "/tikvpb.Tikv/DebugGetRegionProperties",
            .ReadIndex => "/tikvpb.Tikv/ReadIndex",
            .CheckLeader => "/tikvpb.Tikv/CheckLeader", // TODO: un-implemented
            // Others not mapped here yet
            else => null,
        };
    }

    fn decodeResponseForType(self: *Endpoint, t: RequestType, bytes: []const u8) EndpointError!void {
        const A = std.heap.page_allocator;
        var r = std.Io.Reader.fixed(bytes);
        switch (t) {
            .Get => {
                var resp = try kvrpcpb.GetResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "Get: region/key error");
            },
            .Scan => {
                var resp = try kvrpcpb.ScanResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "Scan: region/key error");
            },
            .Prewrite => {
                var resp = try kvrpcpb.PrewriteResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "Prewrite: region/key error");
            },
            .Commit => {
                var resp = try kvrpcpb.CommitResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "Commit: region/key error");
            },
            .Cleanup => {
                var resp = try kvrpcpb.CleanupResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "Cleanup: region/key error");
            },
            .BatchGet => {
                var resp = try kvrpcpb.BatchGetResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "BatchGet: region/key error");
            },
            .BatchRollback => {
                var resp = try kvrpcpb.BatchRollbackResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "BatchRollback: region/key error");
            },
            .ScanLock => {
                var resp = try kvrpcpb.ScanLockResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "ScanLock: region/key error");
            },
            .ResolveLock => {
                var resp = try kvrpcpb.ResolveLockResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "ResolveLock: region/key error");
            },
            .GC => {
                var resp = try kvrpcpb.GCResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "GC: region/key error");
            },
            .DeleteRange => {
                var resp = try kvrpcpb.DeleteRangeResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "DeleteRange: region/key error");
            },
            .RawGet => {
                var resp = try kvrpcpb.RawGetResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "RawGet: region/key error");
            },
            .RawBatchGet => {
                var resp = try kvrpcpb.RawBatchGetResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "RawBatchGet: region/key error");
            },
            .RawPut => {
                var resp = try kvrpcpb.RawPutResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "RawPut: region/key error");
            },
            .RawBatchPut => {
                var resp = try kvrpcpb.RawBatchPutResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "RawBatchPut: region/key error");
            },
            .RawDelete => {
                var resp = try kvrpcpb.RawDeleteResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "RawDelete: region/key error");
            },
            .RawBatchDelete => {
                var resp = try kvrpcpb.RawBatchDeleteResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "RawBatchDelete: region/key error");
            },
            .RawScan => {
                var resp = try kvrpcpb.RawScanResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "RawScan: region/key error");
            },
            .RawDeleteRange => {
                var resp = try kvrpcpb.RawDeleteRangeResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "RawDeleteRange: region/key error");
            },
            .PessimisticLock => {
                var resp = try kvrpcpb.PessimisticLockResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "PessimisticLock: region/key error");
            },
            .PessimisticRollback => {
                var resp = try kvrpcpb.PessimisticRollbackResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "PessimisticRollback: region/key error");
            },
            .CheckTxnStatus => {
                var resp = try kvrpcpb.CheckTxnStatusResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "CheckTxnStatus: region/key error");
            },
            .TxnHeartBeat => {
                var resp = try kvrpcpb.TxnHeartBeatResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "TxnHeartBeat: region/key error");
            },
            .CheckSecondaryLocks => {
                var resp = try kvrpcpb.CheckSecondaryLocksResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "CheckSecondaryLocks: region/key error");
            },
            .ReadIndex => {
                var resp = try kvrpcpb.ReadIndexResponse.decode(&r, A);
                defer resp.deinit(A);
                try self.surfaceKvErrors(&resp, "ReadIndex: region/key error");
            },
            else => {
                // For unimplemented types, do a best-effort no-op
            },
        }
    }

    fn setLastKvError(self: *Endpoint, msg: []const u8) void {
        if (self.last_kv_error) |m| std.heap.page_allocator.free(m);
        self.last_kv_error = std.heap.page_allocator.dupe(u8, msg) catch null;
    }

    fn surfaceKvErrors(self: *Endpoint, resp: anytype, what: []const u8) EndpointError!void {
        comptime {
            if (@hasField(@TypeOf(resp.*), "region_error")) {
                if (resp.region_error != null) {
                    self.setLastKvError(what);
                    return EndpointError.RegionError;
                }
            }
            if (@hasField(@TypeOf(resp.*), "error")) {
                if (resp.@"error" != null) {
                    self.setLastKvError(what);
                    return EndpointError.KeyError;
                }
            }
        }
        return;
    }

    pub fn takeLastGrpcStatus(self: *Endpoint) ?grpc.GrpcStatusInfo {
        const st = self.last_grpc_status;
        self.last_grpc_status = null;
        return st;
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
