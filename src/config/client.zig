// Copyright 2021 TiKV Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

const std = @import("std");

pub const DEF_STORE_LIVENESS_TIMEOUT = "1s";

/// TiKV client configuration
pub const TiKVClient = struct {
    grpc_connection_count: u32,
    grpc_keep_alive_time: u32,
    grpc_keep_alive_timeout: u32,
    grpc_compression_type: []const u8,
    commit_timeout: []const u8,
    async_commit: AsyncCommit,
    max_batch_size: u32,
    overload_threshold: u32,
    max_batch_wait_time: u64, // nanoseconds
    batch_wait_size: u32,
    enable_chunk_rpc: bool,
    region_cache_ttl: u32,
    store_limit: i64,
    store_liveness_timeout: []const u8,
    copr_cache: CoprocessorCache,
    ttl_refreshed_txn_size: i64,
    resolve_lock_lite_threshold: u64,
    
    allocator: std.mem.Allocator,

    pub fn default(allocator: std.mem.Allocator) !TiKVClient {
        return TiKVClient{
            .grpc_connection_count = 4,
            .grpc_keep_alive_time = 10,
            .grpc_keep_alive_timeout = 3,
            .grpc_compression_type = "none",
            .commit_timeout = "41s",
            .async_commit = AsyncCommit.default(),
            .max_batch_size = 128,
            .overload_threshold = 200,
            .max_batch_wait_time = 0,
            .batch_wait_size = 8,
            .enable_chunk_rpc = true,
            .region_cache_ttl = 600,
            .store_limit = 0,
            .store_liveness_timeout = DEF_STORE_LIVENESS_TIMEOUT,
            .copr_cache = CoprocessorCache.default(),
            .ttl_refreshed_txn_size = 32 * 1024 * 1024,
            .resolve_lock_lite_threshold = 16,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TiKVClient) void {
        _ = self;
    }

    pub fn validate(self: *const TiKVClient) !void {
        if (self.grpc_connection_count == 0) {
            return error.InvalidGrpcConnectionCount;
        }
        if (!std.mem.eql(u8, self.grpc_compression_type, "none") and 
            !std.mem.eql(u8, self.grpc_compression_type, "gzip")) {
            return error.InvalidGrpcCompressionType;
        }
    }
};

/// Async commit configuration
pub const AsyncCommit = struct {
    keys_limit: u32,
    total_key_size_limit: u64,
    safe_window: u64, // nanoseconds
    allowed_clock_drift: u64, // nanoseconds

    pub fn default() AsyncCommit {
        return AsyncCommit{
            .keys_limit = 256,
            .total_key_size_limit = 4 * 1024, // 4 KiB
            .safe_window = 2 * std.time.ns_per_s, // 2 seconds
            .allowed_clock_drift = 500 * std.time.ns_per_ms, // 500ms
        };
    }
};

/// Coprocessor cache configuration
pub const CoprocessorCache = struct {
    capacity_mb: f64,
    admission_max_ranges: u64,
    admission_max_result_mb: f64,
    admission_min_process_ms: u64,

    pub fn default() CoprocessorCache {
        return CoprocessorCache{
            .capacity_mb = 1000.0,
            .admission_max_ranges = 500,
            .admission_max_result_mb = 10.0,
            .admission_min_process_ms = 5,
        };
    }
};

test "tikv client validation" {
    const allocator = std.testing.allocator;
    
    var client = try TiKVClient.default(allocator);
    defer client.deinit();
    
    // Test valid configuration
    try client.validate();
    
    // Test invalid grpc connection count
    client.grpc_connection_count = 0;
    try std.testing.expectError(error.InvalidGrpcConnectionCount, client.validate());
    
    // Reset and test invalid compression type
    client.grpc_connection_count = 4;
    client.grpc_compression_type = "invalid";
    try std.testing.expectError(error.InvalidGrpcCompressionType, client.validate());
}

test "async commit defaults" {
    const async_commit = AsyncCommit.default();
    try std.testing.expect(async_commit.keys_limit == 256);
    try std.testing.expect(async_commit.total_key_size_limit == 4 * 1024);
}

test "coprocessor cache defaults" {
    const copr_cache = CoprocessorCache.default();
    try std.testing.expect(copr_cache.capacity_mb == 1000.0);
    try std.testing.expect(copr_cache.admission_max_ranges == 500);
}
