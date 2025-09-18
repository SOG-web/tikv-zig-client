// PD gRPC implementation for ScanRegions
const std = @import("std");
const types = @import("../types.zig");
const client_mod = @import("../grpc_client.zig");
const pdpb = @import("kvproto").pdpb;
const codec_bytes = @import("../../util/codec/bytes.zig");

const Error = types.Error;
const Region = types.Region;

pub fn scanRegions(self: *client_mod.GrpcPDClient, start_key: []const u8, end_key: []const u8, limit: usize) Error![]Region {
    var client_wrapper = try self.getClient(null);

    // Get cluster info for proper headers
    const cluster_info = try self.getClusterInfo();

    // Encode keys using TiKV memcomparable format
    const enc_start_key = codec_bytes.encodeBytes(self.allocator, start_key) catch return Error.OutOfMemory;
    defer self.allocator.free(enc_start_key);

    const enc_end_key = codec_bytes.encodeBytes(self.allocator, end_key) catch return Error.OutOfMemory;
    defer self.allocator.free(enc_end_key);

    // Build ScanRegions request
    var req = pdpb.ScanRegionsRequest{
        .header = pdpb.RequestHeader{
            .cluster_id = cluster_info.cluster_id,
            .sender_id = cluster_info.sender_id,
        },
        .start_key = enc_start_key,
        .end_key = enc_end_key,
        .limit = @intCast(limit),
    };

    // Encode request
    var aw: std.Io.Writer.Allocating = std.Io.Writer.Allocating.init(self.allocator);
    defer aw.deinit();
    req.encode(&aw.writer, self.allocator) catch return Error.RpcError;
    const req_bytes = aw.written();

    // Call PD.ScanRegions
    const resp_bytes = client_wrapper.call("/pdpb.PD/ScanRegions", req_bytes, .gzip, 5000) catch return Error.RpcError;
    defer self.allocator.free(resp_bytes);

    // Decode response
    var reader = std.Io.Reader.fixed(resp_bytes);
    var resp = pdpb.ScanRegionsResponse.decode(&reader, self.allocator) catch return Error.RpcError;
    defer resp.deinit(self.allocator);

    // Extract regions
    var regions = std.ArrayList(Region){};

    try regions.ensureTotalCapacityPrecise(self.allocator, resp.regions.items.len);

    for (resp.regions.items) |re| {
        const rptr = re.region orelse continue; // skip null
        // Deep copy to detach from resp’s allocator-owned memory
        const rcopy = rptr.*.dupe(self.allocator) catch return Error.OutOfMemory;
        try regions.append(self.allocator, rcopy);
    }

    return regions.toOwnedSlice(self.allocator);
}
