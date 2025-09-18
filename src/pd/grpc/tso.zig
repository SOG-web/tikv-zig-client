// PD gRPC implementation for TSO
const std = @import("std");
const types = @import("../types.zig");
const client_mod = @import("../grpc_client.zig");
const tsopb = @import("kvproto").tsopb;

const Error = types.Error;

pub fn getTS(self: *client_mod.GrpcPDClient) Error!types.TSOResult {
    var client_wrapper = try self.getClient(null);

    // Get cluster info for proper headers
    const cluster_info = try self.getClusterInfo();

    // Build TSO request
    var req = tsopb.TsoRequest{
        .header = tsopb.RequestHeader{
            .cluster_id = cluster_info.cluster_id,
            .sender_id = cluster_info.sender_id,
        },
        .count = 1,
        .dc_location = "",
    };

    // Encode request
    var aw: std.Io.Writer.Allocating = std.Io.Writer.Allocating.init(self.allocator);
    defer aw.deinit();
    req.encode(&aw.writer, self.allocator) catch return Error.RpcError;
    const req_bytes = aw.written();

    // Call TSO.Tso
    const resp_bytes = client_wrapper.call("/tsopb.TSO/Tso", req_bytes, .gzip, 5000) catch return Error.RpcError;
    defer self.allocator.free(resp_bytes);

    // Decode response
    var reader = std.Io.Reader.fixed(resp_bytes);
    var resp = tsopb.TsoResponse.decode(&reader, self.allocator) catch return Error.RpcError;
    defer resp.deinit(self.allocator);

    // Extract timestamp
    if (resp.timestamp) |ts| {
        return ts;
    } else {
        return Error.RpcError;
    }
}
