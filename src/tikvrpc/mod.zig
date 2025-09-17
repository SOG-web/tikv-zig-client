// TiKV RPC module (tikvrpc) - compatibility scaffold with Go client
// This file re-exports submodules and provides shared aliases.

const kvproto = @import("kvproto");
pub const kvrpcpb = kvproto.kvrpcpb;
pub const coprocessor = kvproto.coprocessor;

pub const request = @import("request.zig");
pub const endpoint = @import("endpoint.zig");
pub const call = @import("call.zig");
pub const batch = @import("batch.zig");
pub const interceptor = @import("interceptor.zig");
pub const types = @import("types.zig");
pub const codec = @import("codec.zig");
pub const accessors = @import("accessors.zig");

// Re-export primary types for convenience
pub const Request = request.Request;
pub const RequestType = request.RequestType;
pub const RequestOptions = request.RequestOptions;
pub const Priority = request.Priority;
pub const ReplicaRead = request.ReplicaRead;

pub const Endpoint = endpoint.Endpoint;
pub const EndpointError = endpoint.EndpointError;

pub const CallResult = call.CallResult;

pub const RequestBatch = batch.RequestBatch;

pub const Interceptor = interceptor.Interceptor;
pub const EndpointType = types.EndpointType;
pub const Response = codec.Response;
pub const toBatchCommandsRequest = codec.toBatchCommandsRequest;
pub const fromBatchCommandsResponse = codec.fromBatchCommandsResponse;
pub const toBatchCommandsRequests = codec.toBatchCommandsRequests;

test {
    _ = request;
    _ = endpoint;
    _ = call;
    _ = batch;
    _ = interceptor;
}
