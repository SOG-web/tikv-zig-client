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

// NOTE: The code in this file is based on code from the
// TiDB project, licensed under the Apache License v 2.0
//
// https://github.com/pingcap/tidb/tree/cc5e161ac06827589c4966674597c137cc9e809c/store/tikv/config/security.go

const std = @import("std");
const logz = @import("logz");
const openssl = @import("openssl.zig");

/// Security is the security section of the config.
pub const Security = struct {
    cluster_ssl_ca: []const u8,
    cluster_ssl_cert: []const u8,
    cluster_ssl_key: []const u8,
    cluster_verify_cn: []const []const u8,

    allocator: ?std.mem.Allocator,
    /// Whether `cluster_verify_cn` slice container was allocated by this struct and should be freed.
    owns_verify_cn_container: bool = false,
    /// Whether each element in `cluster_verify_cn` was individually allocated and should be freed.
    owns_verify_cn_items: bool = false,
    /// If CNs were packed into a single buffer, this holds that buffer for deallocation.
    verify_cn_packed_buf: ?[]u8 = null,

    /// Create a default Security configuration
    pub fn default() Security {
        return Security{
            .cluster_ssl_ca = "",
            .cluster_ssl_cert = "",
            .cluster_ssl_key = "",
            .cluster_verify_cn = &[_][]const u8{},
            .allocator = null,
            .owns_verify_cn_container = false,
            .owns_verify_cn_items = false,
            .verify_cn_packed_buf = null,
        };
    }

    /// Create a new Security configuration (equivalent to Go's NewSecurity)
    pub fn init(
        allocator: std.mem.Allocator,
        ssl_ca: []const u8,
        ssl_cert: []const u8,
        ssl_key: []const u8,
        verify_cn: []const []const u8,
    ) !Security {
        return Security{
            .cluster_ssl_ca = try allocator.dupe(u8, ssl_ca),
            .cluster_ssl_cert = try allocator.dupe(u8, ssl_cert),
            .cluster_ssl_key = try allocator.dupe(u8, ssl_key),
            .cluster_verify_cn = try allocator.dupe([]const u8, verify_cn),
            .allocator = allocator,
            // Shallow copy of CNs: we own the container but not the inner strings.
            .owns_verify_cn_container = true,
            .owns_verify_cn_items = false,
            .verify_cn_packed_buf = null,
        };
    }

    /// Create a new Security configuration with string literals (no allocation)
    pub fn newSecurity(ssl_ca: []const u8, ssl_cert: []const u8, ssl_key: []const u8, verify_cn: []const []const u8) Security {
        return Security{
            .cluster_ssl_ca = ssl_ca,
            .cluster_ssl_cert = ssl_cert,
            .cluster_ssl_key = ssl_key,
            .cluster_verify_cn = verify_cn,
            .allocator = null,
            .owns_verify_cn_container = false,
            .owns_verify_cn_items = false,
            .verify_cn_packed_buf = null,
        };
    }

    /// Create a Security that takes ownership of CNs by deep-copying each element.
    /// Lifetime: all CN strings and the container live in `allocator` and will be freed by `deinit`.
    pub fn initOwned(
        allocator: std.mem.Allocator,
        ssl_ca: []const u8,
        ssl_cert: []const u8,
        ssl_key: []const u8,
        verify_cn: []const []const u8,
    ) !Security {
        var cn_slices = try allocator.alloc([]const u8, verify_cn.len);
        errdefer allocator.free(cn_slices);

        var i: usize = 0;
        while (i < verify_cn.len) : (i += 1) {
            cn_slices[i] = try allocator.dupe(u8, verify_cn[i]);
        }

        return Security{
            .cluster_ssl_ca = try allocator.dupe(u8, ssl_ca),
            .cluster_ssl_cert = try allocator.dupe(u8, ssl_cert),
            .cluster_ssl_key = try allocator.dupe(u8, ssl_key),
            .cluster_verify_cn = cn_slices,
            .allocator = allocator,
            .owns_verify_cn_container = true,
            .owns_verify_cn_items = true,
            .verify_cn_packed_buf = null,
        };
    }

    /// Create a Security that takes ownership of CNs by packing them into a single contiguous buffer.
    /// Lifetime: the single packed buffer and the container live in `allocator` and will be freed by `deinit`.
    /// Performance: fewer allocations and improved cache locality compared to per-item copies.
    pub fn initOwnedPacked(
        allocator: std.mem.Allocator,
        ssl_ca: []const u8,
        ssl_cert: []const u8,
        ssl_key: []const u8,
        verify_cn: []const []const u8,
    ) !Security {
        // Compute total size needed.
        var total: usize = 0;
        for (verify_cn) |cn| total += cn.len;

        // Allocate one contiguous buffer for all CN strings.
        var buf = try allocator.alloc(u8, total);
        errdefer allocator.free(buf);

        // Allocate the slice container.
        var cn_slices = try allocator.alloc([]const u8, verify_cn.len);
        errdefer allocator.free(cn_slices);

        // Copy strings into the packed buffer and set slices into it.
        var off: usize = 0;
        var i: usize = 0;
        while (i < verify_cn.len) : (i += 1) {
            const src = verify_cn[i];
            const dst = buf[off .. off + src.len];
            std.mem.copy(u8, dst, src);
            cn_slices[i] = dst; // []u8 coerces to []const u8
            off += src.len;
        }

        return Security{
            .cluster_ssl_ca = try allocator.dupe(u8, ssl_ca),
            .cluster_ssl_cert = try allocator.dupe(u8, ssl_cert),
            .cluster_ssl_key = try allocator.dupe(u8, ssl_key),
            .cluster_verify_cn = cn_slices,
            .allocator = allocator,
            .owns_verify_cn_container = true,
            .owns_verify_cn_items = false,
            .verify_cn_packed_buf = buf,
        };
    }

    /// Free all resources owned by this Security according to ownership flags.
    ///
    /// Lifetimes:
    /// - `default` / `newSecurity`: does not free CN container or items (no ownership).
    /// - `init`: frees CN container only (shallow copy).
    /// - `initOwned`: frees CN container and each CN item.
    /// - `initOwnedPacked`: frees CN container and the single packed buffer.
    pub fn deinit(self: *Security) void {
        if (self.allocator) |allocator| {
            if (self.cluster_ssl_ca.len > 0) allocator.free(self.cluster_ssl_ca);
            if (self.cluster_ssl_cert.len > 0) allocator.free(self.cluster_ssl_cert);
            if (self.cluster_ssl_key.len > 0) allocator.free(self.cluster_ssl_key);

            if (self.owns_verify_cn_items) {
                for (self.cluster_verify_cn) |cn| {
                    if (cn.len > 0) allocator.free(cn);
                }
            }

            if (self.verify_cn_packed_buf) |buf| {
                allocator.free(buf);
                self.verify_cn_packed_buf = null;
            }

            if (self.owns_verify_cn_container and self.cluster_verify_cn.len > 0) {
                allocator.free(self.cluster_verify_cn);
            }
        }
    }

    /// Generate TLS config based on security section of the config (equivalent to Go's ToTLSConfig)
    pub fn toTLSConfig(self: *const Security, allocator: std.mem.Allocator) !?TLSConfig {
        if (self.cluster_ssl_ca.len == 0) {
            return null;
        }

        // Initialize OpenSSL if not already done
        openssl.initOpenSSL();

        // Create SSL context
        var ssl_ctx = openssl.SSLContext.init() catch |err| {
            if (@import("builtin").is_test) {
                std.debug.print("Could not create SSL context: {}\n", .{err});
            } else {
                logz.err().ctx("Security.toTLSConfig").err(err).log("Could not create SSL context");
            }
            return err;
        };

        // Set verification mode
        ssl_ctx.setVerify(openssl.SSL_VERIFY_PEER);

        // Read and load CA certificate
        const ca_data = std.fs.cwd().readFileAlloc(allocator, self.cluster_ssl_ca, 1024 * 1024) catch |err| {
            if (@import("builtin").is_test) {
                std.debug.print("Could not read CA certificate: {}\n", .{err});
            } else {
                logz.err().ctx("Security.toTLSConfig").err(err).string("ca_file", self.cluster_ssl_ca).log("Could not read CA certificate");
            }
            ssl_ctx.deinit();
            return err;
        };
        defer allocator.free(ca_data);

        ssl_ctx.loadCAFromMemory(ca_data) catch |err| {
            if (@import("builtin").is_test) {
                std.debug.print("Could not load CA certificate: {}\n", .{err});
            } else {
                logz.err().ctx("Security.toTLSConfig").err(err).log("Could not load CA certificate");
            }
            ssl_ctx.deinit();
            return err;
        };

        // Load client certificates if provided
        if (self.cluster_ssl_cert.len > 0 and self.cluster_ssl_key.len > 0) {
            const cert_data = std.fs.cwd().readFileAlloc(allocator, self.cluster_ssl_cert, 1024 * 1024) catch |err| {
                if (@import("builtin").is_test) {
                    std.debug.print("Could not read client certificate: {}\n", .{err});
                } else {
                    logz.err().ctx("Security.toTLSConfig").err(err).string("cert_file", self.cluster_ssl_cert).log("Could not read client certificate");
                }
                ssl_ctx.deinit();
                return err;
            };
            defer allocator.free(cert_data);

            const key_data = std.fs.cwd().readFileAlloc(allocator, self.cluster_ssl_key, 1024 * 1024) catch |err| {
                if (@import("builtin").is_test) {
                    std.debug.print("Could not read client key: {}\n", .{err});
                } else {
                    logz.err().ctx("Security.toTLSConfig").err(err).string("key_file", self.cluster_ssl_key).log("Could not read client key");
                }
                ssl_ctx.deinit();
                return err;
            };
            defer allocator.free(key_data);

            ssl_ctx.loadClientCert(cert_data, key_data) catch |err| {
                if (@import("builtin").is_test) {
                    std.debug.print("Could not load client certificate: {}\n", .{err});
                } else {
                    logz.err().ctx("Security.toTLSConfig").err(err).log("Could not load client certificate");
                }
                ssl_ctx.deinit();
                return err;
            };
        }

        return TLSConfig{
            .ssl_context = ssl_ctx,
            .verify_cn = self.cluster_verify_cn,
            .allocator = allocator,
        };
    }

    /// Check if TLS is enabled
    pub fn isTLSEnabled(self: *const Security) bool {
        return self.cluster_ssl_ca.len > 0;
    }

    /// Validate security configuration
    pub fn validate(self: *const Security) !void {
        // If CA is provided, it must be a valid file path
        if (self.cluster_ssl_ca.len > 0) {
            std.fs.cwd().access(self.cluster_ssl_ca, .{}) catch |err| switch (err) {
                error.FileNotFound => return error.InvalidCAFile,
                else => return err,
            };
        }

        // If cert is provided, key must also be provided
        if (self.cluster_ssl_cert.len > 0 and self.cluster_ssl_key.len == 0) {
            return error.MissingSSLKey;
        }

        // If key is provided, cert must also be provided
        if (self.cluster_ssl_key.len > 0 and self.cluster_ssl_cert.len == 0) {
            return error.MissingSSLCert;
        }
    }
};

/// TLS configuration (equivalent to Go's tls.Config)
pub const TLSConfig = struct {
    ssl_context: openssl.SSLContext,
    verify_cn: []const []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *TLSConfig) void {
        self.ssl_context.deinit();
    }

    /// Check if client authentication is enabled
    pub fn hasClientAuth(self: *const TLSConfig) bool {
        // This would require checking if client certificates are loaded in the SSL context
        // For now, we assume client auth is available if we have an SSL context
        return self.ssl_context.ctx != null;
    }

    /// Create an SSL connection using this TLS config
    pub fn createConnection(self: *TLSConfig, socket_fd: std.os.socket_t) !openssl.SSLConnection {
        return openssl.SSLConnection.init(&self.ssl_context, @intCast(socket_fd));
    }
};

test "security config default" {
    var security = Security.default();
    defer security.deinit();

    try std.testing.expect(security.cluster_ssl_ca.len == 0);
    try std.testing.expect(security.cluster_verify_cn.len == 0);
    try std.testing.expect(!security.isTLSEnabled());
}

test "security config newSecurity" {
    var verify_cn = [_][]const u8{ "test.example.com", "*.example.com" };
    var security = Security.newSecurity("ca.pem", "cert.pem", "key.pem", verify_cn[0..]);
    defer security.deinit();

    try std.testing.expectEqualStrings("ca.pem", security.cluster_ssl_ca);
    try std.testing.expectEqualStrings("cert.pem", security.cluster_ssl_cert);
    try std.testing.expectEqualStrings("key.pem", security.cluster_ssl_key);
    try std.testing.expect(security.cluster_verify_cn.len == 2);
    try std.testing.expect(security.isTLSEnabled());
}

test "security config validation" {
    var security = Security.default();
    defer security.deinit();

    // Default config should be valid
    try security.validate();

    // Test missing key error
    security.cluster_ssl_cert = "cert.pem";
    try std.testing.expectError(error.MissingSSLKey, security.validate());

    // Test missing cert error
    security.cluster_ssl_cert = "";
    security.cluster_ssl_key = "key.pem";
    try std.testing.expectError(error.MissingSSLCert, security.validate());
}
