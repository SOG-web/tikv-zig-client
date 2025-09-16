// PD gRPC implementation for GetAllStores (scaffold)
const std = @import("std");
const types = @import("../types.zig");
const client_mod = @import("../grpc_client.zig");

const Error = types.Error;
const Store = types.Store;

pub fn getAllStores(self: *client_mod.GrpcPDClient) Error![]Store {
    _ = self;
    return Error.Unimplemented; // TODO: implement with gRPC-zig pdpb.PD.GetAllStores
}
