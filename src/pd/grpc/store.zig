// PD gRPC implementation for GetStore
const std = @import("std");
const types = @import("../types.zig");
const client_mod = @import("../grpc_client.zig");
const pdpb = @import("kvproto").pdpb;

const Error = types.Error;
const Store = types.Store;

pub fn getStore(self: *client_mod.GrpcPDClient, store_id: u64) Error!Store {
    var client_wrapper = try self.getClient(null);

    // Get cluster info for proper headers
    const cluster_info = try self.getClusterInfo();

    // Build GetStore request
    var req = pdpb.GetStoreRequest{
        .header = pdpb.RequestHeader{
            .cluster_id = cluster_info.cluster_id,
            .sender_id = cluster_info.sender_id,
        },
        .store_id = store_id,
    };

    // Encode request
    var aw: std.Io.Writer.Allocating = std.Io.Writer.Allocating.init(self.allocator);
    defer aw.deinit();
    req.encode(&aw.writer, self.allocator) catch return Error.RpcError;
    const req_bytes = aw.written();

    // Call PD.GetStore
    const resp_bytes = client_wrapper.call("/pdpb.PD/GetStore", req_bytes, .gzip, 5000) catch return Error.RpcError;
    defer self.allocator.free(resp_bytes);

    // Decode response
    var reader = std.Io.Reader.fixed(resp_bytes);
    var resp = pdpb.GetStoreResponse.decode(&reader, self.allocator) catch return Error.RpcError;
    defer resp.deinit(self.allocator);

    // Extract store - deep copy before resp.deinit frees decoder-owned memory
    if (resp.store) |store| {
        const copy = store.dupe(self.allocator) catch return Error.OutOfMemory;
        return copy;
    } else {
        return Error.NotFound;
    }
}
