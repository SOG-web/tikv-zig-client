// PD gRPC implementation for GetAllStores
const std = @import("std");
const types = @import("../types.zig");
const client_mod = @import("../grpc_client.zig");
const pdpb = @import("kvproto").pdpb;

const Error = types.Error;
const Store = types.Store;

pub fn getAllStores(self: *client_mod.GrpcPDClient) Error![]Store {
    var client_wrapper = try self.getClient(null);

    // Get cluster info for proper headers
    const cluster_info = try self.getClusterInfo();

    // Build GetAllStores request
    var req = pdpb.GetAllStoresRequest{
        .header = pdpb.RequestHeader{
            .cluster_id = cluster_info.cluster_id,
            .sender_id = cluster_info.sender_id,
        },
        .exclude_tombstone_stores = true, // Exclude tombstone stores by default
    };

    // Encode request
    var aw: std.Io.Writer.Allocating = std.Io.Writer.Allocating.init(self.allocator);
    defer aw.deinit();
    req.encode(&aw.writer, self.allocator) catch return Error.RpcError;
    const req_bytes = aw.written();

    // Call PD.GetAllStores
    const resp_bytes = client_wrapper.call("/pdpb.PD/GetAllStores", req_bytes, .gzip, 5000) catch return Error.RpcError;
    defer self.allocator.free(resp_bytes);

    // Decode response
    var reader = std.Io.Reader.fixed(resp_bytes);
    var resp = pdpb.GetAllStoresResponse.decode(&reader, self.allocator) catch return Error.RpcError;
    defer resp.deinit(self.allocator);

    // Extract stores
    var stores = std.ArrayList(Store){};
    defer stores.deinit(self.allocator);

    try stores.ensureTotalCapacityPrecise(self.allocator, resp.stores.items.len);

    for (resp.stores.items) |store| {
        try stores.append(self.allocator, store);
    }

    return stores.toOwnedSlice(self.allocator);
}
