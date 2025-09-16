# TiKV Client-Zig: OpenSSL Local Setup Guide

This document explains how to set up OpenSSL locally within the repository for TLS support in the TiKV client-zig project.

## Overview

The TiKV client requires TLS/SSL support for secure connections to TiKV servers. Instead of relying on system-installed OpenSSL (which varies across systems), we build OpenSSL locally within the repository to ensure consistent builds.

## Prerequisites

### Required Tools
- **Zig 0.15.1+** - For building the project
- **CMake 3.10+** - For building OpenSSL
- **Make** - For OpenSSL build system
- **Git** - For cloning dependencies
- **C Compiler** (gcc/clang) - For compiling OpenSSL

### Install Dependencies

```bash
# macOS with Homebrew
brew install cmake make git

# Ubuntu/Debian
sudo apt-get install cmake make git build-essential

# Verify installations
cmake --version    # Should show cmake 3.10+
make --version     # Should show GNU Make
zig version        # Should show 0.15.1+
```

## Project Structure

```
client-zig/
├── third_party/
│   ├── _openssl_src/          # OpenSSL source (3.1.x)
│   └── openssl-build/         # Built OpenSSL libraries
│       ├── include/           # OpenSSL headers
│       ├── lib/               # Static libraries (libssl.a, libcrypto.a)
│       └── bin/               # OpenSSL tools
├── scripts/
│   └── build_openssl.sh       # OpenSSL build script
└── src/
    └── config/
        ├── openssl.zig        # OpenSSL C bindings
        └── security.zig       # TLS security configuration
```

## Setup Steps

### 1. Clone OpenSSL Source

```bash
# From project root
git clone --depth 1 --branch openssl-3.1.4 \
  https://github.com/openssl/openssl.git third_party/_openssl_src
```

### 2. Build OpenSSL Locally

```bash
# Run the build script
./scripts/build_openssl.sh
```

This script:
- Configures OpenSSL for static linking
- Builds libssl.a and libcrypto.a
- Installs headers and libraries to `third_party/openssl-build/`
- Creates optimized builds for the target platform

### 3. Build and Test

```bash
# Build the project (now uses local OpenSSL)
zig build

# Run tests (includes TLS functionality tests)
zig build test
```

## Generated Files

The build process creates:

### Libraries
- `third_party/openssl-build/lib/libssl.a` - SSL/TLS protocol library
- `third_party/openssl-build/lib/libcrypto.a` - Cryptographic functions library

### Headers
- `third_party/openssl-build/include/openssl/*.h` - OpenSSL C headers
- Key headers: `ssl.h`, `crypto.h`, `x509.h`, `pem.h`, `bio.h`

### Tools (Optional)
- `third_party/openssl-build/bin/openssl` - OpenSSL command-line tool

## Usage in Zig

```zig
const std = @import("std");
const openssl = @import("config/openssl.zig");

test "TLS connection" {
    const allocator = std.testing.allocator;
    
    // Initialize OpenSSL
    openssl.initOpenSSL();
    
    // Create SSL context
    var ssl_ctx = try openssl.SSLContext.init();
    defer ssl_ctx.deinit();
    
    // Configure for client connections
    ssl_ctx.setVerify(openssl.SSL_VERIFY_PEER);
    
    // Load CA certificate
    const ca_data = "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----";
    try ssl_ctx.loadCAFromMemory(ca_data);
    
    // Create SSL connection (with actual socket)
    // var ssl_conn = try openssl.SSLConnection.init(&ssl_ctx, socket_fd);
    // defer ssl_conn.deinit();
    // try ssl_conn.connect();
}
```

## Build Integration

The build.zig file automatically:
- Links against local OpenSSL static libraries
- Includes OpenSSL headers from the local build
- Handles cross-platform library paths

```zig
// In build.zig
const openssl_path = "third_party/openssl-build";
exe.addIncludePath(b.path(openssl_path ++ "/include"));
exe.addLibraryPath(b.path(openssl_path ++ "/lib"));
exe.linkSystemLibrary("ssl");
exe.linkSystemLibrary("crypto");
```

## Troubleshooting

### Common Issues

**"OpenSSL not found" during build**
- Ensure `./scripts/build_openssl.sh` completed successfully
- Check that `third_party/openssl-build/lib/` contains libssl.a and libcrypto.a
- Verify include path contains OpenSSL headers

**Build script fails**
- Install required build tools (cmake, make, gcc/clang)
- Check that `third_party/_openssl_src/` exists and contains OpenSSL source
- Ensure write permissions in `third_party/` directory

**Zig compilation errors**
- Use Zig 0.15+ for modern C import syntax
- Check that OpenSSL headers are compatible with your target platform
- Verify static library architecture matches your build target

**Runtime SSL errors**
- Initialize OpenSSL with `openssl.initOpenSSL()` before use
- Check certificate paths and formats
- Verify that CA certificates are valid and accessible

### Rebuilding OpenSSL

To rebuild OpenSSL (e.g., after updates or configuration changes):

```bash
# Clean existing build
rm -rf third_party/openssl-build

# Rebuild
./scripts/build_openssl.sh
```

### Cross-Platform Builds

The build script automatically detects the platform and configures OpenSSL accordingly:
- **macOS**: Uses clang with optimizations for Apple Silicon/Intel
- **Linux**: Uses gcc with standard optimizations
- **Windows**: Uses MinGW or MSVC (requires additional setup)

## Architecture Notes

### Why Local OpenSSL?
- **Consistency**: Same OpenSSL version across all development/deployment environments
- **Security**: Control over OpenSSL version and security patches
- **Performance**: Optimized builds for specific target platforms
- **Portability**: No dependency on system OpenSSL installation

### Static vs Dynamic Linking
- Uses static linking (libssl.a, libcrypto.a) for simpler deployment
- No runtime dependency on system OpenSSL libraries
- Larger binary size but better portability

### Security Considerations
- OpenSSL 3.1.4 includes latest security patches
- Regular updates recommended for security fixes
- Static linking prevents conflicts with system OpenSSL versions

## Performance Considerations

- Static libraries are optimized for the target platform
- Consider enabling OpenSSL assembly optimizations for production builds
- Profile TLS handshake performance in your specific use case
- Monitor memory usage with long-lived SSL contexts

## Version Compatibility

- **OpenSSL**: 3.1.4 (LTS version with security support until 2026)
- **Zig**: 0.15.1+ (for modern C import and linking features)
- **CMake**: 3.10+ (required by OpenSSL build system)

For updates, check OpenSSL release notes for API compatibility and security fixes.
