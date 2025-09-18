// PD client interface for Zig
// This defines a vtable-based client so we can swap implementations (e.g., gRPC).

const std = @import("std");
const types = @import("types.zig");
const grpc_impl = @import("grpc_client.zig");

pub const Error = types.Error;
pub const Region = types.Region;
pub const Store = types.Store;
pub const KeyRange = types.KeyRange;

/// Timestamp result returned by PD TSO
pub const TSOResult = types.TSOResult;

/// PDClient is a thin interface over PD operations used by TiKV client
pub const PDClient = struct {
    ptr: *grpc_impl.GrpcPDClient,
    vtable: *const VTable,

    pub const VTable = struct {
        // TSO
        getTS: *const fn (ptr: *anyopaque) Error!TSOResult,
        getLocalTS: *const fn (ptr: *anyopaque, scope: []const u8) Error!TSOResult,

        // Region APIs
        getRegion: *const fn (ptr: *anyopaque, key: []const u8, need_buckets: bool) Error!Region,
        getPrevRegion: *const fn (ptr: *anyopaque, key: []const u8, need_buckets: bool) Error!Region,
        getRegionByID: *const fn (ptr: *anyopaque, region_id: u64, need_buckets: bool) Error!Region,
        scanRegions: *const fn (ptr: *anyopaque, start_key: []const u8, end_key: []const u8, limit: usize) Error![]Region,

        // Store APIs
        getStore: *const fn (ptr: *anyopaque, store_id: u64) Error!Store,
        getAllStores: *const fn (ptr: *anyopaque) Error![]Store,

        // Lifecycle
        close: *const fn (ptr: *anyopaque) void,
    };

    pub fn getTS(self: PDClient) Error!TSOResult {
        return self.vtable.getTS(self.ptr);
    }

    pub fn getLocalTS(self: PDClient, scope: []const u8) Error!TSOResult {
        return self.vtable.getLocalTS(self.ptr, scope);
    }

    pub fn getRegion(self: PDClient, key: []const u8, need_buckets: bool) Error!Region {
        return self.vtable.getRegion(self.ptr, key, need_buckets);
    }

    pub fn getPrevRegion(self: PDClient, key: []const u8, need_buckets: bool) Error!Region {
        return self.vtable.getPrevRegion(self.ptr, key, need_buckets);
    }

    pub fn getRegionByID(self: PDClient, region_id: u64, need_buckets: bool) Error!Region {
        return self.vtable.getRegionByID(self.ptr, region_id, need_buckets);
    }

    pub fn scanRegions(self: PDClient, start_key: []const u8, end_key: []const u8, limit: usize) Error![]Region {
        return self.vtable.scanRegions(self.ptr, start_key, end_key, limit);
    }

    pub fn getStore(self: PDClient, store_id: u64) Error!Store {
        return self.vtable.getStore(self.ptr, store_id);
    }

    pub fn getAllStores(self: PDClient) Error![]Store {
        return self.vtable.getAllStores(self.ptr);
    }

    pub fn close(self: PDClient) void {
        self.vtable.close(self.ptr);
    }
};

/// Factory helpers for creating PD clients
pub const PDClientFactory = struct {
    /// Create a gRPC-based PD client using the given endpoints
    pub fn grpc(allocator: std.mem.Allocator, endpoints: []const []const u8) Error!PDClient {
        const impl = try grpc_impl.GrpcPDClient.init(allocator, endpoints);
        return PDClient{
            .ptr = impl,
            .vtable = &.{
                .getTS = grpc_impl.GrpcPDClient.getTS,
                .getLocalTS = grpc_impl.GrpcPDClient.getLocalTS,
                .getRegion = grpc_impl.GrpcPDClient.getRegion,
                .getPrevRegion = grpc_impl.GrpcPDClient.getPrevRegion,
                .getRegionByID = grpc_impl.GrpcPDClient.getRegionByID,
                .scanRegions = grpc_impl.GrpcPDClient.scanRegions,
                .getStore = grpc_impl.GrpcPDClient.getStore,
                .getAllStores = grpc_impl.GrpcPDClient.getAllStores,
                .close = grpc_impl.GrpcPDClient.close,
            },
        };
    }

    /// Create a PD client with explicit transport preference
    pub fn grpc_with_options(allocator: std.mem.Allocator, endpoints: []const []const u8, prefer_grpc: bool, grpc_config: grpc_impl.GrpcConfig) Error!PDClient {
        const impl = try grpc_impl.GrpcPDClient.initWithConfig(allocator, endpoints, grpc_config);
        impl.prefer_grpc = prefer_grpc;
        return PDClient{
            .ptr = impl,
            .vtable = &.{
                .getTS = grpc_impl.GrpcPDClient.getTS,
                .getLocalTS = grpc_impl.GrpcPDClient.getLocalTS,
                .getRegion = grpc_impl.GrpcPDClient.getRegion,
                .getPrevRegion = grpc_impl.GrpcPDClient.getPrevRegion,
                .getRegionByID = grpc_impl.GrpcPDClient.getRegionByID,
                .scanRegions = grpc_impl.GrpcPDClient.scanRegions,
                .getStore = grpc_impl.GrpcPDClient.getStore,
                .getAllStores = grpc_impl.GrpcPDClient.getAllStores,
                .close = grpc_impl.GrpcPDClient.close,
            },
        };
    }

    /// Create a PD client with transport and HTTPS options
    pub fn grpc_with_transport_options(
        allocator: std.mem.Allocator,
        endpoints: []const []const u8,
        prefer_grpc: bool,
        use_https: bool,
        grpc_config: grpc_impl.GrpcConfig,
    ) Error!PDClient {
        const impl = try grpc_impl.GrpcPDClient.initWithConfig(allocator, endpoints, grpc_config);
        impl.prefer_grpc = prefer_grpc;
        impl.use_https = use_https;
        return PDClient{
            .ptr = impl,
            .vtable = &.{
                .getTS = grpc_impl.GrpcPDClient.getTS,
                .getLocalTS = grpc_impl.GrpcPDClient.getLocalTS,
                .getRegion = grpc_impl.GrpcPDClient.getRegion,
                .getPrevRegion = grpc_impl.GrpcPDClient.getPrevRegion,
                .getRegionByID = grpc_impl.GrpcPDClient.getRegionByID,
                .scanRegions = grpc_impl.GrpcPDClient.scanRegions,
                .getStore = grpc_impl.GrpcPDClient.getStore,
                .getAllStores = grpc_impl.GrpcPDClient.getAllStores,
                .close = grpc_impl.GrpcPDClient.close,
            },
        };
    }
};

test {
    std.testing.refAllDecls(@This());
}
