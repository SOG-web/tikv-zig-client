// PD gRPC implementation for ScanRegions (scaffold)
const std = @import("std");
const types = @import("../types.zig");
const client_mod = @import("../grpc_client.zig");

const Error = types.Error;
const Region = types.Region;

pub fn scanRegions(self: *client_mod.GrpcPDClient, start_key: []const u8, end_key: []const u8, limit: usize, need_buckets: bool) Error![]Region {
    _ = self; _ = start_key; _ = end_key; _ = limit; _ = need_buckets;
    return Error.Unimplemented; // TODO: implement with gRPC-zig pdpb.PD.ScanRegions
}
