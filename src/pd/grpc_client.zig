// Stub gRPC-based PD client implementation.
// This file provides a compilable placeholder. Real gRPC logic will be added.

const std = @import("std");
const types = @import("types.zig");
const http = std.http; // kept for future methods
const json = std.json; // kept for future methods
const Uri = std.Uri; // kept for future methods
const grpc = @import("../grpc_client/mod.zig");
const pool = @import("../grpc_client/pool.zig");
const tls = grpc.tls;
const http2_integration = grpc.http2_integration;
const pdpb = @import("kvproto").pdpb;
const tsopb = @import("kvproto").tsopb;
const region_http = @import("http/region.zig");
const region_grpc = @import("grpc/region.zig");
const region_by_id_http = @import("http/region_by_id.zig");
const region_by_id_grpc = @import("grpc/region_by_id.zig");
const scan_regions_http = @import("http/scan_regions.zig");
const scan_regions_grpc = @import("grpc/scan_regions.zig");
const tctx = @import("transport_ctx.zig");
const store_http = @import("http/store.zig");
const store_grpc = @import("grpc/store.zig");
const stores_http = @import("http/stores.zig");
const stores_grpc = @import("grpc/stores.zig");
const prev_region_grpc = @import("grpc/prev_region.zig");
const tso_grpc = @import("grpc/tso.zig");
const codec_bytes = @import("../util/codec/bytes.zig");

pub const Error = types.Error;
pub const Region = types.Region;
pub const Store = types.Store;
const KeyRange = types.KeyRange;

// File-scope logical counter for dev-only TSO fallback
var g_tso_logical: std.atomic.Value(i64) = std.atomic.Value(i64).init(0);

// Zig version now supports both PD HTTP and gRPC clients. gRPC is enabled by default
// with graceful fallback to HTTP for unimplemented methods. TSO and GetRegion are
// implemented via gRPC using the new HTTP/2 client with HPACK compression.

const ClusterInfo = struct {
    cluster_id: u64,
    sender_id: u64,
};

pub const GrpcConfig = struct {
    use_connection_pool: bool = true,
    max_connections_per_host: u32 = 10,
    connection_timeout_seconds: u32 = 300,
    max_concurrent_streams: u32 = 100,
};

pub const ClientWrapper = union(enum) {
    single: *grpc.GrpcClient,
    multiplexed: pool.MultiplexedClient,

    pub fn call(
        self: *ClientWrapper,
        path: []const u8,
        request: []const u8,
        compression_alg: @import("../grpc_client/features/compression.zig").Compression.Algorithm,
        timeout_ms: ?u64,
    ) ![]u8 {
        switch (self.*) {
            .single => |client| return client.call(path, request, compression_alg, timeout_ms),
            .multiplexed => |*client| return client.call(path, request, compression_alg, timeout_ms),
        }
    }
};

pub const GrpcPDClient = struct {
    allocator: std.mem.Allocator,
    endpoints: [][]const u8,
    prefer_grpc: bool,
    use_https: bool,
    http_client: std.http.Client,
    tls: TlsOptions,
    grpc_client: ?*grpc.GrpcClient,
    client_pool: ?*pool.ClientPool,
    cluster_info: ?ClusterInfo,
    grpc_config: GrpcConfig,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, endpoints: []const []const u8) Error!*Self {
        return initWithConfig(allocator, endpoints, GrpcConfig{});
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, endpoints: []const []const u8, config: GrpcConfig) Error!*Self {
        var self = allocator.create(Self) catch return Error.OutOfMemory;
        self.* = .{
            .allocator = allocator,
            .endpoints = try allocator.alloc([]const u8, endpoints.len),
            .prefer_grpc = true, // Enable gRPC by default now
            .use_https = false,
            .http_client = .{ .allocator = allocator },
            .tls = .{},
            .grpc_client = null,
            .client_pool = null,
            .cluster_info = null,
            .grpc_config = config,
        };
        for (endpoints, 0..) |ep, i| {
            self.endpoints[i] = try allocator.dupe(u8, ep);
        }
        // Centralized place to wire TLS options to the HTTP client when supported by std.http in this Zig version.
        self.applyTlsOptions();
        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.grpc_client) |client| {
            client.deinit();
            self.allocator.destroy(client);
        }
        if (self.client_pool) |pool_ptr| {
            pool_ptr.deinit();
            self.allocator.destroy(pool_ptr);
        }
        self.http_client.deinit();
        for (self.endpoints) |ep| self.allocator.free(ep);
        self.allocator.free(self.endpoints);
        self.allocator.destroy(self);
    }

    // Helper to get or create gRPC client for first endpoint with TLS support
    pub fn getGrpcClient(self: *Self) Error!*grpc.GrpcClient {
        if (self.grpc_client) |client| return client;

        if (self.endpoints.len == 0) return Error.RpcError;

        // Parse first endpoint
        const endpoint = self.endpoints[0];
        const colon_pos = std.mem.lastIndexOfScalar(u8, endpoint, ':') orelse return Error.RpcError;
        const host = endpoint[0..colon_pos];
        const port_str = endpoint[colon_pos + 1 ..];
        const port = std.fmt.parseInt(u16, port_str, 10) catch return Error.RpcError;

        // Create gRPC client with TLS support
        const client = self.allocator.create(grpc.GrpcClient) catch return Error.OutOfMemory;
        if (self.use_https) {
            // Convert TlsOptions to tls.TlsConfig
            const tls_config = tls.TlsConfig{
                .server_name = self.tls.server_name orelse host,
                .insecure_skip_verify = self.tls.insecure_skip_verify,
                .ca_cert_pem = self.tls.ca_pem,
                .client_cert_pem = self.tls.client_cert_pem,
                .client_key_pem = self.tls.client_key_pem,
                .alpn_protocols = self.tls.alpn_protocols,
            };
            client.* = grpc.GrpcClient.initWithTls(self.allocator, host, port, tls_config) catch return Error.RpcError;
        } else {
            client.* = grpc.GrpcClient.init(self.allocator, host, port) catch return Error.RpcError;
        }
        self.grpc_client = client;

        return client;
    }

    pub fn initWithTls(self: *Self, allocator: std.mem.Allocator, host: []const u8, port: u16, tls_config: tls.TlsConfig) Error!*Self {
        self.* = self.init(allocator, host, port) catch return Error.OutOfMemory;
        self.use_https = true;
        self.tls = tls_config;
        return self;
    }

    // Create HTTP/2 connection with TLS + ALPN
    pub fn createHttp2Connection(self: *Self, endpoint_idx: ?usize) Error!*http2_integration.Http2TlsConnection {
        if (self.endpoints.len == 0) return Error.RpcError;

        const idx = endpoint_idx orelse 0;
        const endpoint = self.endpoints[idx];

        // Parse endpoint
        const colon_pos = std.mem.lastIndexOfScalar(u8, endpoint, ':') orelse return Error.RpcError;
        const host = endpoint[0..colon_pos];
        const port_str = endpoint[colon_pos + 1 ..];
        const port = std.fmt.parseInt(u16, port_str, 10) catch return Error.RpcError;

        // Create HTTP/2 connection
        const connection = self.allocator.create(http2_integration.Http2TlsConnection) catch return Error.OutOfMemory;

        if (self.use_https) {
            const tls_config = tls.TlsConfig{
                .server_name = self.tls.server_name orelse host,
                .insecure_skip_verify = self.tls.insecure_skip_verify,
                .ca_cert_pem = self.tls.ca_pem,
                .client_cert_pem = self.tls.client_cert_pem,
                .client_key_pem = self.tls.client_key_pem,
                .alpn_protocols = &.{"h2"},
            };
            connection.* = http2_integration.Http2TlsConnection.init(self.allocator, host, port, true, tls_config) catch return Error.RpcError;
        } else {
            connection.* = http2_integration.Http2TlsConnection.init(self.allocator, host, port, false, null) catch return Error.RpcError;
        }

        return connection;
    }

    // Helper to get or create connection pool for efficient connection management
    pub fn getClientPool(self: *Self) Error!*pool.ClientPool {
        if (self.client_pool) |pool_ptr| return pool_ptr;

        // Create connection pool for efficient connection reuse
        const pool_ptr = self.allocator.create(pool.ClientPool) catch return Error.OutOfMemory;
        pool_ptr.* = pool.ClientPool.init(self.allocator);
        self.client_pool = pool_ptr;

        return pool_ptr;
    }

    // Get a multiplexed client for a specific endpoint (round-robin selection)
    pub fn getMultiplexedClient(self: *Self, endpoint_idx: ?usize) Error!pool.MultiplexedClient {
        const pool_ptr = try self.getClientPool();

        if (self.endpoints.len == 0) return Error.RpcError;

        // Use round-robin or specified endpoint
        const idx = endpoint_idx orelse (std.crypto.random.int(usize) % self.endpoints.len);
        const endpoint = self.endpoints[idx];

        // Parse endpoint
        const colon_pos = std.mem.lastIndexOfScalar(u8, endpoint, ':') orelse return Error.RpcError;
        const host = endpoint[0..colon_pos];
        const port_str = endpoint[colon_pos + 1 ..];
        const port = std.fmt.parseInt(u16, port_str, 10) catch return Error.RpcError;

        return pool_ptr.getClient(host, port) catch return Error.RpcError;
    }

    // Get the appropriate client based on configuration (pooled or single)
    pub fn getClient(self: *Self, endpoint_idx: ?usize) Error!ClientWrapper {
        if (self.grpc_config.use_connection_pool) {
            const multiplexed = try self.getMultiplexedClient(endpoint_idx);
            return ClientWrapper{ .multiplexed = multiplexed };
        } else {
            const single = try self.getGrpcClient();
            return ClientWrapper{ .single = single };
        }
    }

    // Helper to get cluster info (lazy initialization via GetClusterInfo)
    pub fn getClusterInfo(self: *Self) Error!ClusterInfo {
        if (self.cluster_info) |info| return info;

        // Get cluster info via GetClusterInfo call
        const client_wrapper = try self.getClient(null);

        // Build GetClusterInfo request
        var req = pdpb.GetClusterInfoRequest{};

        // Encode request
        var aw: std.Io.Writer.Allocating = std.Io.Writer.Allocating.init(self.allocator);
        defer aw.deinit();
        req.encode(&aw.writer, self.allocator) catch return Error.RpcError;
        const req_bytes = aw.written();

        // Call PD.GetClusterInfo
        var client_wrapper_mut = client_wrapper;
        const resp_bytes = client_wrapper_mut.call("/pdpb.PD/GetClusterInfo", req_bytes, .gzip, 5000) catch return Error.RpcError;
        defer self.allocator.free(resp_bytes);

        // Decode response
        var reader = std.Io.Reader.fixed(resp_bytes);
        var resp = pdpb.GetClusterInfoResponse.decode(&reader, self.allocator) catch return Error.RpcError;
        defer resp.deinit(self.allocator);

        // Extract cluster info
        const cluster_id = if (resp.header) |h| h.cluster_id else 0;
        const sender_id = std.crypto.random.int(u64); // Generate random sender ID

        const info = ClusterInfo{
            .cluster_id = cluster_id,
            .sender_id = sender_id,
        };
        self.cluster_info = info;

        return info;
    }

    pub fn getTS(ptr: *anyopaque) Error!types.TSOResult {
        const self: *Self = @ptrCast(@alignCast(ptr));
        if (self.prefer_grpc) {
            return tso_grpc.getTS(self) catch |err| switch (err) {
                Error.Unimplemented, Error.RpcError => {
                    // Fallback to synthetic TSO
                    std.log.warn("PD TSO via gRPC failed, using synthetic fallback: {}", .{err});
                    const nanos: i128 = std.time.nanoTimestamp();
                    const millis: i64 = @intCast(@divTrunc(nanos, std.time.ns_per_ms));
                    const logical: i64 = g_tso_logical.fetchAdd(1, .monotonic);
                    return types.TSOResult{ .physical = millis, .logical = logical };
                },
                else => return err,
            };
        }

        // Compose a monotonic-ish TSO from system time and a process-local logical counter.
        const nanos: i128 = std.time.nanoTimestamp();
        const millis: i64 = @intCast(@divTrunc(nanos, std.time.ns_per_ms));
        const logical: i64 = g_tso_logical.fetchAdd(1, .monotonic);
        return types.TSOResult{ .physical = millis, .logical = logical };
    }

    pub fn getLocalTS(ptr: *anyopaque, scope: []const u8) Error!types.TSOResult {
        _ = scope;
        return getTS(ptr);
    }

    pub fn getRegion(ptr: *anyopaque, key: []const u8, need_buckets: bool) Error!Region {
        const self: *Self = @ptrCast(@alignCast(ptr));
        if (self.prefer_grpc) {
            return region_grpc.getRegion(self, key, need_buckets) catch |err| switch (err) {
                Error.Unimplemented, Error.RpcError => {
                    // Fallback to HTTP
                    std.log.warn("PD GetRegion via gRPC failed, using HTTP fallback: {}", .{err});
                    var ctx: tctx.TransportCtx = .{
                        .allocator = self.allocator,
                        .endpoints = self.endpoints,
                        .use_https = self.use_https,
                    };
                    return region_http.getRegion(&ctx, &self.http_client, key, need_buckets);
                },
                else => return err,
            };
        } else {
            var ctx: tctx.TransportCtx = .{
                .allocator = self.allocator,
                .endpoints = self.endpoints,
                .use_https = self.use_https,
            };
            return region_http.getRegion(&ctx, &self.http_client, key, need_buckets);
        }
    }

    pub fn getPrevRegion(ptr: *anyopaque, key: []const u8, need_buckets: bool) Error!Region {
        const self: *Self = @ptrCast(@alignCast(ptr));
        if (self.prefer_grpc) {
            return prev_region_grpc.getPrevRegion(self, key, need_buckets) catch |err| switch (err) {
                Error.Unimplemented, Error.RpcError => {
                    // Fallback to HTTP
                    std.log.warn("PD GetPrevRegion via gRPC failed, using HTTP fallback: {}", .{err});
                    // var ctx: tctx.TransportCtx = .{
                    //     .allocator = self.allocator,
                    //     .endpoints = self.endpoints,
                    //     .use_https = self.use_https,
                    // };
                    const start_key: []const u8 = &[_]u8{}; // empty start
                    const end_key: []const u8 = key;
                    const limit: usize = 512;
                    const regions = scan_regions_grpc.scanRegions(self, start_key, end_key, limit) catch |e| switch (e) {
                        error.OutOfMemory => return Error.OutOfMemory,
                        else => return Error.RpcError,
                    };
                    defer self.allocator.free(regions);
                    if (regions.len == 0) return Error.NotFound;
                    return regions[regions.len - 1];
                },
                else => return err,
            };
        }

        // HTTP fallback approximation:
        // scan regions from start to `key` and pick the last region in the response.
        var ctx: tctx.TransportCtx = .{
            .allocator = self.allocator,
            .endpoints = self.endpoints,
            .use_https = self.use_https,
        };
        const start_key: []const u8 = &[_]u8{}; // empty start
        const end_key: []const u8 = key;
        // Limit: use a reasonable cap (e.g., 512) to avoid large responses
        const limit: usize = 512;
        const regions = scan_regions_http.scanRegions(&ctx, &self.http_client, start_key, end_key, limit) catch |err| {
            return switch (err) {
                error.OutOfMemory => Error.OutOfMemory,
                else => Error.RpcError,
            };
        };
        defer self.allocator.free(regions);
        if (regions.len == 0) return Error.NotFound;
        return regions[regions.len - 1];
    }

    pub fn getRegionByID(ptr: *anyopaque, region_id: u64, need_buckets: bool) Error!Region {
        const self: *Self = @ptrCast(@alignCast(ptr));
        if (self.prefer_grpc) {
            return region_by_id_grpc.getRegionByID(self, region_id, need_buckets) catch |err| switch (err) {
                Error.Unimplemented, Error.RpcError => {
                    // Fallback to HTTP
                    std.log.warn("PD GetRegionByID via gRPC failed, using HTTP fallback: {}", .{err});
                    var ctx: tctx.TransportCtx = .{
                        .allocator = self.allocator,
                        .endpoints = self.endpoints,
                        .use_https = self.use_https,
                    };
                    return region_by_id_http.getRegionByID(&ctx, &self.http_client, region_id, need_buckets);
                },
                else => return err,
            };
        } else {
            var ctx: tctx.TransportCtx = .{
                .allocator = self.allocator,
                .endpoints = self.endpoints,
                .use_https = self.use_https,
            };
            return region_by_id_http.getRegionByID(&ctx, &self.http_client, region_id, need_buckets);
        }
    }

    pub fn scanRegions(ptr: *anyopaque, start_key: []const u8, end_key: []const u8, limit: usize) Error![]Region {
        const self: *Self = @ptrCast(@alignCast(ptr));
        if (self.prefer_grpc) {
            return scan_regions_grpc.scanRegions(self, start_key, end_key, limit) catch |err| switch (err) {
                Error.Unimplemented, Error.RpcError => {
                    // Fallback to HTTP
                    std.log.warn("PD ScanRegions via gRPC failed, using HTTP fallback: {}", .{err});
                    var ctx: tctx.TransportCtx = .{
                        .allocator = self.allocator,
                        .endpoints = self.endpoints,
                        .use_https = self.use_https,
                    };
                    return scan_regions_http.scanRegions(&ctx, &self.http_client, start_key, end_key, limit);
                },
                else => return err,
            };
        } else {
            var ctx: tctx.TransportCtx = .{
                .allocator = self.allocator,
                .endpoints = self.endpoints,
                .use_https = self.use_https,
            };
            return scan_regions_http.scanRegions(&ctx, &self.http_client, start_key, end_key, limit);
        }
    }

    pub fn getStore(ptr: *anyopaque, store_id: u64) Error!Store {
        const self: *Self = @ptrCast(@alignCast(ptr));
        if (self.prefer_grpc) {
            return store_grpc.getStore(self, store_id) catch |err| switch (err) {
                Error.Unimplemented, Error.RpcError => {
                    // Fallback to HTTP
                    std.log.warn("PD GetStore via gRPC failed, using HTTP fallback: {}", .{err});
                    var ctx: tctx.TransportCtx = .{
                        .allocator = self.allocator,
                        .endpoints = self.endpoints,
                        .use_https = self.use_https,
                    };
                    return store_http.getStore(&ctx, &self.http_client, store_id);
                },
                else => return err,
            };
        } else {
            var ctx: tctx.TransportCtx = .{
                .allocator = self.allocator,
                .endpoints = self.endpoints,
                .use_https = self.use_https,
            };
            return store_http.getStore(&ctx, &self.http_client, store_id);
        }
    }

    pub fn getAllStores(ptr: *anyopaque) Error![]Store {
        const self: *Self = @ptrCast(@alignCast(ptr));
        if (self.prefer_grpc) {
            return stores_grpc.getAllStores(self) catch |err| switch (err) {
                Error.Unimplemented, Error.RpcError => {
                    // Fallback to HTTP
                    std.log.warn("PD GetAllStores via gRPC failed, using HTTP fallback: {}", .{err});
                    var ctx: tctx.TransportCtx = .{
                        .allocator = self.allocator,
                        .endpoints = self.endpoints,
                        .use_https = self.use_https,
                    };
                    return stores_http.getAllStores(&ctx, &self.http_client);
                },
                else => return err,
            };
        } else {
            var ctx: tctx.TransportCtx = .{
                .allocator = self.allocator,
                .endpoints = self.endpoints,
                .use_https = self.use_https,
            };
            return stores_http.getAllStores(&ctx, &self.http_client);
        }
    }

    pub fn close(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.deinit();
    }

    fn applyTlsOptions(self: *GrpcPDClient) void {
        //TODO: Later fix
        // We document and log the requested options so users have visibility.
        if (!self.use_https) return;

        if (self.tls.insecure_skip_verify) {
            std.log.warn("TLS insecure_skip_verify requested but not supported by std.http.Client in Zig 0.15.1; using system defaults", .{});
        }
        if (self.tls.server_name) |name| {
            std.log.warn("TLS server_name override '{s}' requested but not supported by std.http.Client in Zig 0.15.1", .{name});
        }
        if (self.tls.ca_pem) |_| {
            std.log.warn("Custom CA bundle provided, but std.http.Client in Zig 0.15.1 cannot install it; using system roots", .{});
        }
    }
};

pub const TlsOptions = struct {
    // When true, do not verify server certificate (dev only). Default false.
    insecure_skip_verify: bool = false,
    // Override SNI/ServerName for certificate verification.
    server_name: ?[]const u8 = null,
    // Optional CA bundle PEM bytes provided at runtime (no hardcoding).
    ca_pem: ?[]const u8 = null,
    // Client certificate for mutual TLS
    client_cert_pem: ?[]const u8 = null,
    // Client private key for mutual TLS
    client_key_pem: ?[]const u8 = null,
    // ALPN protocols to negotiate
    alpn_protocols: []const []const u8 = &.{"h2"},
};

pub fn setTlsOptions(self: *GrpcPDClient, opts: TlsOptions) void {
    self.tls = opts;
    self.applyTlsOptions();
}
