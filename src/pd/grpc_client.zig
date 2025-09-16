// Stub gRPC-based PD client implementation.
// This file provides a compilable placeholder. Real gRPC logic will be added.

const std = @import("std");
const types = @import("types.zig");
const http = std.http; // kept for future methods
const json = std.json; // kept for future methods
const Uri = std.Uri; // kept for future methods
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

pub const Error = types.Error;
pub const Region = types.Region;
pub const Store = types.Store;
const KeyRange = types.KeyRange;

// File-scope logical counter for dev-only TSO fallback
var g_tso_logical: std.atomic.Value(i64) = std.atomic.Value(i64).init(0);

// TODO(cascade): Zig version currently uses PD HTTP client; TSO is a dev-only synthetic
// fallback in `pd/grpc_client.zig` until gRPC TSO is wired. When gRPC TSO is implemented,
// set `prefer_grpc = true` and Oracle/clients will use it transparently.

pub const GrpcPDClient = struct {
    allocator: std.mem.Allocator,
    endpoints: [][]const u8,
    prefer_grpc: bool,
    use_https: bool,
    http_client: std.http.Client,
    tls: TlsOptions,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, endpoints: []const []const u8) Error!*Self {
        var self = allocator.create(Self) catch return Error.OutOfMemory;
        self.* = .{
            .allocator = allocator,
            .endpoints = try allocator.alloc([]const u8, endpoints.len),
            .prefer_grpc = false,
            .use_https = false,
            .http_client = .{ .allocator = allocator },
            .tls = .{},
        };
        for (endpoints, 0..) |ep, i| {
            self.endpoints[i] = try allocator.dupe(u8, ep);
        }
        // Centralized place to wire TLS options to the HTTP client when supported by std.http in this Zig version.
        self.applyTlsOptions();
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.http_client.deinit();
        for (self.endpoints) |ep| self.allocator.free(ep);
        self.allocator.free(self.endpoints);
        self.allocator.destroy(self);
    }

    // VTable functions

    pub fn getTS(ptr: *anyopaque) Error!types.TSOResult {
        const self: *Self = @ptrCast(@alignCast(ptr));
        if (self.prefer_grpc) {
            // Real gRPC-based TSO not wired yet in this module
            return Error.Unimplemented;
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
            return region_grpc.getRegion(self, key, need_buckets);
        } else {
            var ctx: tctx.TransportCtx = .{
                .allocator = self.allocator,
                .endpoints = self.endpoints,
                .use_https = self.use_https,
            };
            return region_http.getRegion(&ctx, &self.http_client, key, need_buckets);
        }
    }

    // HTTP helpers moved into http/region.zig and reused there.

    pub fn getPrevRegion(ptr: *anyopaque, key: []const u8, need_buckets: bool) Error!Region {
        const self: *Self = @ptrCast(@alignCast(ptr));
        if (self.prefer_grpc) {
            return prev_region_grpc.getPrevRegion(self, key, need_buckets);
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
        const regions = scan_regions_http.scanRegions(&ctx, &self.http_client, start_key, end_key, limit, need_buckets) catch |err| {
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
            return region_by_id_grpc.getRegionByID(self, region_id, need_buckets);
        } else {
            var ctx: tctx.TransportCtx = .{
                .allocator = self.allocator,
                .endpoints = self.endpoints,
                .use_https = self.use_https,
            };
            return region_by_id_http.getRegionByID(&ctx, &self.http_client, region_id, need_buckets);
        }
    }

    pub fn scanRegions(ptr: *anyopaque, start_key: []const u8, end_key: []const u8, limit: usize, need_buckets: bool) Error![]Region {
        const self: *Self = @ptrCast(@alignCast(ptr));
        if (self.prefer_grpc) {
            return scan_regions_grpc.scanRegions(self, start_key, end_key, limit, need_buckets);
        } else {
            var ctx: tctx.TransportCtx = .{
                .allocator = self.allocator,
                .endpoints = self.endpoints,
                .use_https = self.use_https,
            };
            return scan_regions_http.scanRegions(&ctx, &self.http_client, start_key, end_key, limit, need_buckets);
        }
    }

    pub fn getStore(ptr: *anyopaque, store_id: u64) Error!Store {
        const self: *Self = @ptrCast(@alignCast(ptr));
        if (self.prefer_grpc) {
            return store_grpc.getStore(self, store_id);
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
            return stores_grpc.getAllStores(self);
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
};

pub fn setTlsOptions(self: *GrpcPDClient, opts: TlsOptions) void {
    self.tls = opts;
    self.applyTlsOptions();
}
