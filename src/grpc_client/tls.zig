// TLS + ALPN support for gRPC client
const std = @import("std");
const c = @cImport({
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
    @cInclude("openssl/x509.h");
    @cInclude("openssl/x509v3.h");
});

pub const TlsError = error{
    InitializationFailed,
    ConnectionFailed,
    HandshakeFailed,
    CertificateVerificationFailed,
    AlpnNegotiationFailed,
    OutOfMemory,
};

pub const TlsConfig = struct {
    /// Skip certificate verification (for testing only)
    insecure_skip_verify: bool = false,
    /// Custom CA certificate bundle (PEM format)
    ca_cert_pem: ?[]const u8 = null,
    /// Server name for SNI
    server_name: ?[]const u8 = null,
    /// ALPN protocols to negotiate (e.g., ["h2", "http/1.1"])
    alpn_protocols: []const []const u8 = &.{"h2"},
    /// Client certificate for mutual TLS
    client_cert_pem: ?[]const u8 = null,
    /// Client private key for mutual TLS
    client_key_pem: ?[]const u8 = null,
};

pub const TlsConnection = struct {
    ssl: *c.SSL,
    ctx: *c.SSL_CTX,
    socket: std.posix.socket_t,
    allocator: std.mem.Allocator,
    negotiated_protocol: ?[]const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, socket: std.posix.socket_t, config: TlsConfig) TlsError!Self {
        // Initialize OpenSSL if not already done
        _ = c.SSL_library_init();
        c.SSL_load_error_strings();
        c.OpenSSL_add_all_algorithms();

        // Create SSL context
        const method = c.TLS_client_method();
        const ctx = c.SSL_CTX_new(method) orelse return TlsError.InitializationFailed;
        errdefer c.SSL_CTX_free(ctx);

        // Configure context
        try configureSslContext(ctx, config);

        // Create SSL connection
        const ssl = c.SSL_new(ctx) orelse return TlsError.InitializationFailed;
        errdefer c.SSL_free(ssl);

        // Set socket
        if (c.SSL_set_fd(ssl, @intCast(socket)) != 1) {
            return TlsError.ConnectionFailed;
        }

        // Set SNI if provided
        if (config.server_name) |server_name| {
            const server_name_z = try allocator.dupeZ(u8, server_name);
            defer allocator.free(server_name_z);
            if (c.SSL_set_tlsext_host_name(ssl, server_name_z.ptr) != 1) {
                return TlsError.ConnectionFailed;
            }
        }

        // Perform handshake
        const handshake_result = c.SSL_connect(ssl);
        if (handshake_result != 1) {
            const ssl_error = c.SSL_get_error(ssl, handshake_result);
            std.log.err("TLS handshake failed: SSL error {}", .{ssl_error});
            return TlsError.HandshakeFailed;
        }

        // Verify certificate if not skipping
        if (!config.insecure_skip_verify) {
            const verify_result = c.SSL_get_verify_result(ssl);
            if (verify_result != c.X509_V_OK) {
                std.log.err("Certificate verification failed: {}", .{verify_result});
                return TlsError.CertificateVerificationFailed;
            }
        }

        // Get negotiated ALPN protocol
        var negotiated_protocol: ?[]const u8 = null;
        var alpn_data: [*c]const u8 = undefined;
        var alpn_len: c_uint = undefined;
        c.SSL_get0_alpn_selected(ssl, &alpn_data, &alpn_len);
        if (alpn_len > 0) {
            negotiated_protocol = try allocator.dupe(u8, alpn_data[0..alpn_len]);
        }

        return Self{
            .ssl = ssl,
            .ctx = ctx,
            .socket = socket,
            .allocator = allocator,
            .negotiated_protocol = negotiated_protocol,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.negotiated_protocol) |protocol| {
            self.allocator.free(protocol);
        }
        c.SSL_shutdown(self.ssl);
        c.SSL_free(self.ssl);
        c.SSL_CTX_free(self.ctx);
    }

    pub fn read(self: *Self, buffer: []u8) !usize {
        const result = c.SSL_read(self.ssl, buffer.ptr, @intCast(buffer.len));
        if (result <= 0) {
            const ssl_error = c.SSL_get_error(self.ssl, result);
            if (ssl_error == c.SSL_ERROR_WANT_READ or ssl_error == c.SSL_ERROR_WANT_WRITE) {
                return 0; // Would block
            }
            return error.ConnectionClosed;
        }
        return @intCast(result);
    }

    pub fn write(self: *Self, data: []const u8) !usize {
        const result = c.SSL_write(self.ssl, data.ptr, @intCast(data.len));
        if (result <= 0) {
            const ssl_error = c.SSL_get_error(self.ssl, result);
            if (ssl_error == c.SSL_ERROR_WANT_READ or ssl_error == c.SSL_ERROR_WANT_WRITE) {
                return 0; // Would block
            }
            return error.ConnectionClosed;
        }
        return @intCast(result);
    }

    pub fn writeAll(self: *Self, data: []const u8) !void {
        var written: usize = 0;
        while (written < data.len) {
            const n = try self.write(data[written..]);
            if (n == 0) return error.ConnectionClosed;
            written += n;
        }
    }

    pub fn readAll(self: *Self, buffer: []u8) !void {
        var read_bytes: usize = 0;
        while (read_bytes < buffer.len) {
            const n = try self.read(buffer[read_bytes..]);
            if (n == 0) return error.ConnectionClosed;
            read_bytes += n;
        }
    }

    pub fn isHttp2(self: *Self) bool {
        if (self.negotiated_protocol) |protocol| {
            return std.mem.eql(u8, protocol, "h2");
        }
        return false;
    }
};

fn configureSslContext(ctx: *c.SSL_CTX, config: TlsConfig) TlsError!void {
    // Set minimum TLS version to 1.2
    if (c.SSL_CTX_set_min_proto_version(ctx, c.TLS1_2_VERSION) != 1) {
        return TlsError.InitializationFailed;
    }

    // Configure ALPN
    if (config.alpn_protocols.len > 0) {
        var alpn_list = std.ArrayList(u8).init(std.heap.c_allocator);
        defer alpn_list.deinit();

        for (config.alpn_protocols) |protocol| {
            try alpn_list.append(@intCast(protocol.len));
            try alpn_list.appendSlice(protocol);
        }

        if (c.SSL_CTX_set_alpn_protos(ctx, alpn_list.items.ptr, @intCast(alpn_list.items.len)) != 0) {
            return TlsError.AlpnNegotiationFailed;
        }
    }

    // Configure certificate verification
    if (config.insecure_skip_verify) {
        c.SSL_CTX_set_verify(ctx, c.SSL_VERIFY_NONE, null);
    } else {
        c.SSL_CTX_set_verify(ctx, c.SSL_VERIFY_PEER, null);
        
        // Load default CA certificates
        if (c.SSL_CTX_set_default_verify_paths(ctx) != 1) {
            std.log.warn("Failed to load default CA certificates", .{});
        }

        // Load custom CA certificate if provided
        if (config.ca_cert_pem) |ca_pem| {
            const bio = c.BIO_new_mem_buf(ca_pem.ptr, @intCast(ca_pem.len));
            defer c.BIO_free(bio);

            const cert = c.PEM_read_bio_X509(bio, null, null, null);
            if (cert) |c_cert| {
                defer c.X509_free(c_cert);
                const store = c.SSL_CTX_get_cert_store(ctx);
                if (c.X509_STORE_add_cert(store, c_cert) != 1) {
                    return TlsError.InitializationFailed;
                }
            }
        }
    }

    // Configure client certificate if provided
    if (config.client_cert_pem) |cert_pem| {
        const bio = c.BIO_new_mem_buf(cert_pem.ptr, @intCast(cert_pem.len));
        defer c.BIO_free(bio);

        const cert = c.PEM_read_bio_X509(bio, null, null, null);
        if (cert) |c_cert| {
            defer c.X509_free(c_cert);
            if (c.SSL_CTX_use_certificate(ctx, c_cert) != 1) {
                return TlsError.InitializationFailed;
            }
        }
    }

    // Configure client private key if provided
    if (config.client_key_pem) |key_pem| {
        const bio = c.BIO_new_mem_buf(key_pem.ptr, @intCast(key_pem.len));
        defer c.BIO_free(bio);

        const key = c.PEM_read_bio_PrivateKey(bio, null, null, null);
        if (key) |c_key| {
            defer c.EVP_PKEY_free(c_key);
            if (c.SSL_CTX_use_PrivateKey(ctx, c_key) != 1) {
                return TlsError.InitializationFailed;
            }
        }
    }
}

test "tls config creation" {
    const config = TlsConfig{
        .alpn_protocols = &.{ "h2", "http/1.1" },
        .server_name = "example.com",
    };
    
    try std.testing.expect(config.alpn_protocols.len == 2);
    try std.testing.expect(std.mem.eql(u8, config.alpn_protocols[0], "h2"));
}
