// PD gRPC implementation for GetPrevRegion
const std = @import("std");
const types = @import("../types.zig");
const client_mod = @import("../grpc_client.zig");
const pdpb = @import("kvproto").pdpb;
const codec_bytes = @import("../../util/codec/bytes.zig");

const Error = types.Error;
const Region = types.Region;

pub fn getPrevRegion(self: *client_mod.GrpcPDClient, key: []const u8, need_buckets: bool) Error!Region {
    var client_wrapper = try self.getClient(null);

    // Get cluster info for proper headers
    const cluster_info = try self.getClusterInfo();

    // Encode key using TiKV memcomparable format
    const enc_key = codec_bytes.encodeBytes(self.allocator, key) catch return Error.OutOfMemory;
    defer self.allocator.free(enc_key);

    // Build GetPrevRegion request
    var req = pdpb.GetRegionRequest{
        .header = pdpb.RequestHeader{
            .cluster_id = cluster_info.cluster_id,
            .sender_id = cluster_info.sender_id,
        },
        .region_key = enc_key,
        .need_buckets = need_buckets,
    };

    // Encode request
    var aw: std.Io.Writer.Allocating = std.Io.Writer.Allocating.init(self.allocator);
    defer aw.deinit();
    req.encode(&aw.writer, self.allocator) catch return Error.RpcError;
    const req_bytes = aw.written();

    // Call PD.GetPrevRegion
    const resp_bytes = client_wrapper.call("/pdpb.PD/GetPrevRegion", req_bytes, .gzip, 5000) catch return Error.RpcError;
    defer self.allocator.free(resp_bytes);

    // Decode response
    var reader = std.Io.Reader.fixed(resp_bytes);
    var resp = pdpb.GetRegionResponse.decode(&reader, self.allocator) catch return Error.RpcError;
    defer resp.deinit(self.allocator);

    // Extract region
    if (resp.region) |region| {
        return region;
    } else {
        return Error.NotFound;
    }
}
