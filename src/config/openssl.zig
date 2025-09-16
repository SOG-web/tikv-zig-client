// Copyright 2025 SOG-web
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
const c = @cImport({
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
    @cInclude("openssl/x509.h");
    @cInclude("openssl/x509v3.h");
    @cInclude("openssl/pem.h");
    @cInclude("openssl/bio.h");
    @cInclude("openssl/evp.h");
    @cInclude("openssl/crypto.h");
});

pub const SSL_CTX = c.SSL_CTX;
pub const SSL = c.SSL;
pub const X509 = c.X509;
pub const X509_STORE = c.X509_STORE;
pub const BIO = c.BIO;
pub const EVP_PKEY = c.EVP_PKEY;

// SSL context methods
pub const SSLv23_client_method = c.SSLv23_client_method;
pub const TLS_client_method = c.TLS_client_method;

// SSL context functions
pub const SSL_CTX_new = c.SSL_CTX_new;
pub const SSL_CTX_free = c.SSL_CTX_free;
pub const SSL_CTX_set_verify = c.SSL_CTX_set_verify;
pub const SSL_CTX_load_verify_locations = c.SSL_CTX_load_verify_locations;
pub const SSL_CTX_use_certificate = c.SSL_CTX_use_certificate;
pub const SSL_CTX_use_PrivateKey = c.SSL_CTX_use_PrivateKey;
pub const SSL_CTX_check_private_key = c.SSL_CTX_check_private_key;
pub const SSL_CTX_set_default_verify_paths = c.SSL_CTX_set_default_verify_paths;

// SSL functions
pub const SSL_new = c.SSL_new;
pub const SSL_free = c.SSL_free;
pub const SSL_set_fd = c.SSL_set_fd;
pub const SSL_connect = c.SSL_connect;
pub const SSL_read = c.SSL_read;
pub const SSL_write = c.SSL_write;
pub const SSL_shutdown = c.SSL_shutdown;
pub const SSL_get_error = c.SSL_get_error;

// BIO functions
pub const BIO_new_mem_buf = c.BIO_new_mem_buf;
pub const BIO_free = c.BIO_free;

// PEM functions
pub const PEM_read_bio_X509 = c.PEM_read_bio_X509;
pub const PEM_read_bio_PrivateKey = c.PEM_read_bio_PrivateKey;

// X509 functions
pub const X509_free = c.X509_free;

// EVP functions
pub const EVP_PKEY_free = c.EVP_PKEY_free;

// Error functions
pub const ERR_get_error = c.ERR_get_error;
pub const ERR_error_string = c.ERR_error_string;
pub const ERR_clear_error = c.ERR_clear_error;

// SSL library initialization (OpenSSL 3.x compatible)
pub const OPENSSL_init_ssl = c.OPENSSL_init_ssl;
pub const OPENSSL_init_crypto = c.OPENSSL_init_crypto;
pub const OPENSSL_INIT_LOAD_SSL_STRINGS = c.OPENSSL_INIT_LOAD_SSL_STRINGS;
pub const OPENSSL_INIT_LOAD_CRYPTO_STRINGS = c.OPENSSL_INIT_LOAD_CRYPTO_STRINGS;

// SSL constants
pub const SSL_VERIFY_NONE = c.SSL_VERIFY_NONE;
pub const SSL_VERIFY_PEER = c.SSL_VERIFY_PEER;
pub const SSL_VERIFY_FAIL_IF_NO_PEER_CERT = c.SSL_VERIFY_FAIL_IF_NO_PEER_CERT;

// SSL error constants
pub const SSL_ERROR_NONE = c.SSL_ERROR_NONE;
pub const SSL_ERROR_ZERO_RETURN = c.SSL_ERROR_ZERO_RETURN;
pub const SSL_ERROR_WANT_READ = c.SSL_ERROR_WANT_READ;
pub const SSL_ERROR_WANT_WRITE = c.SSL_ERROR_WANT_WRITE;
pub const SSL_ERROR_SYSCALL = c.SSL_ERROR_SYSCALL;
pub const SSL_ERROR_SSL = c.SSL_ERROR_SSL;

/// Initialize OpenSSL library (OpenSSL 3.x compatible)
pub fn initOpenSSL() void {
    _ = OPENSSL_init_ssl(OPENSSL_INIT_LOAD_SSL_STRINGS, null);
    _ = OPENSSL_init_crypto(OPENSSL_INIT_LOAD_CRYPTO_STRINGS, null);
}

/// Get OpenSSL error string
pub fn getErrorString() []const u8 {
    const err = ERR_get_error();
    if (err == 0) return "No error";

    const err_str = ERR_error_string(err, null);
    if (err_str == null) return "Unknown error";

    return std.mem.span(err_str);
}

/// Clear OpenSSL error queue
pub fn clearErrors() void {
    ERR_clear_error();
}

/// SSL Context wrapper
pub const SSLContext = struct {
    ctx: ?*SSL_CTX,

    pub fn init() !SSLContext {
        const method = TLS_client_method();
        if (method == null) return error.SSLMethodFailed;

        const ctx = SSL_CTX_new(method);
        if (ctx == null) return error.SSLContextFailed;

        return SSLContext{ .ctx = ctx };
    }

    pub fn deinit(self: *SSLContext) void {
        if (self.ctx) |ctx| {
            SSL_CTX_free(ctx);
            self.ctx = null;
        }
    }

    pub fn setVerify(self: *SSLContext, mode: c_int) void {
        if (self.ctx) |ctx| {
            SSL_CTX_set_verify(ctx, mode, null);
        }
    }

    pub fn loadCAFromMemory(self: *SSLContext, ca_data: []const u8) !void {
        if (self.ctx == null) return error.InvalidContext;

        const bio = BIO_new_mem_buf(ca_data.ptr, @intCast(ca_data.len));
        if (bio == null) return error.BIOCreateFailed;
        defer BIO_free(bio);

        const cert = PEM_read_bio_X509(bio, null, null, null);
        if (cert == null) return error.CertificateLoadFailed;
        defer X509_free(cert);

        const store = c.SSL_CTX_get_cert_store(self.ctx);
        if (store == null) return error.CertStoreGetFailed;

        if (c.X509_STORE_add_cert(store, cert) != 1) {
            return error.CertStoreAddFailed;
        }
    }

    pub fn loadClientCert(self: *SSLContext, cert_data: []const u8, key_data: []const u8) !void {
        if (self.ctx == null) return error.InvalidContext;

        // Load certificate
        const cert_bio = BIO_new_mem_buf(cert_data.ptr, @intCast(cert_data.len));
        if (cert_bio == null) return error.BIOCreateFailed;
        defer BIO_free(cert_bio);

        const cert = PEM_read_bio_X509(cert_bio, null, null, null);
        if (cert == null) return error.CertificateLoadFailed;
        defer X509_free(cert);

        if (SSL_CTX_use_certificate(self.ctx, cert) != 1) {
            return error.CertificateUseFailed;
        }

        // Load private key
        const key_bio = BIO_new_mem_buf(key_data.ptr, @intCast(key_data.len));
        if (key_bio == null) return error.BIOCreateFailed;
        defer BIO_free(key_bio);

        const key = PEM_read_bio_PrivateKey(key_bio, null, null, null);
        if (key == null) return error.PrivateKeyLoadFailed;
        defer EVP_PKEY_free(key);

        if (SSL_CTX_use_PrivateKey(self.ctx, key) != 1) {
            return error.PrivateKeyUseFailed;
        }

        // Verify private key matches certificate
        if (SSL_CTX_check_private_key(self.ctx) != 1) {
            return error.PrivateKeyMismatch;
        }
    }
};

/// SSL Connection wrapper
pub const SSLConnection = struct {
    ssl: ?*SSL,
    socket_fd: c_int,

    pub fn init(ctx: *SSLContext, socket_fd: c_int) !SSLConnection {
        if (ctx.ctx == null) return error.InvalidContext;

        const ssl = SSL_new(ctx.ctx);
        if (ssl == null) return error.SSLCreateFailed;

        if (SSL_set_fd(ssl, socket_fd) != 1) {
            SSL_free(ssl);
            return error.SSLSetFdFailed;
        }

        return SSLConnection{
            .ssl = ssl,
            .socket_fd = socket_fd,
        };
    }

    pub fn deinit(self: *SSLConnection) void {
        if (self.ssl) |ssl| {
            _ = SSL_shutdown(ssl);
            SSL_free(ssl);
            self.ssl = null;
        }
    }

    pub fn connect(self: *SSLConnection) !void {
        if (self.ssl == null) return error.InvalidSSL;

        const result = SSL_connect(self.ssl);
        if (result != 1) {
            const err = SSL_get_error(self.ssl, result);
            switch (err) {
                SSL_ERROR_WANT_READ => return error.SSLWantRead,
                SSL_ERROR_WANT_WRITE => return error.SSLWantWrite,
                SSL_ERROR_SYSCALL => return error.SSLSyscallError,
                SSL_ERROR_SSL => return error.SSLProtocolError,
                else => return error.SSLConnectFailed,
            }
        }
    }

    pub fn read(self: *SSLConnection, buffer: []u8) !usize {
        if (self.ssl == null) return error.InvalidSSL;

        const result = SSL_read(self.ssl, buffer.ptr, @intCast(buffer.len));
        if (result <= 0) {
            const err = SSL_get_error(self.ssl, result);
            switch (err) {
                SSL_ERROR_WANT_READ => return error.SSLWantRead,
                SSL_ERROR_WANT_WRITE => return error.SSLWantWrite,
                SSL_ERROR_ZERO_RETURN => return error.SSLConnectionClosed,
                SSL_ERROR_SYSCALL => return error.SSLSyscallError,
                SSL_ERROR_SSL => return error.SSLProtocolError,
                else => return error.SSLReadFailed,
            }
        }

        return @intCast(result);
    }

    pub fn write(self: *SSLConnection, data: []const u8) !usize {
        if (self.ssl == null) return error.InvalidSSL;

        const result = SSL_write(self.ssl, data.ptr, @intCast(data.len));
        if (result <= 0) {
            const err = SSL_get_error(self.ssl, result);
            switch (err) {
                SSL_ERROR_WANT_READ => return error.SSLWantRead,
                SSL_ERROR_WANT_WRITE => return error.SSLWantWrite,
                SSL_ERROR_SYSCALL => return error.SSLSyscallError,
                SSL_ERROR_SSL => return error.SSLProtocolError,
                else => return error.SSLWriteFailed,
            }
        }

        return @intCast(result);
    }
};
