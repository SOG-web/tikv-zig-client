# Status: Early Development

This library is under active development. Some components compile and tests are being brought up incrementally. Expect breaking changes.

# TiKV Client for Zig

A Zig client library for TiKV, the distributed transactional key-value database.

## Features

- Raw KV operations (Get, Put, Delete, Scan)
- Transactional KV operations (2PC, optimistic transactions)
- Async/await support
- Connection pooling
- Error handling with TiKV-specific error types

## Requirements

- Zig 0.15.1 or later
- TiKV cluster (for integration tests)

## Setup

### Quick Setup
This project now uses a Zig-native protobuf pipeline (no C/UPB). Generated files live under `src/proto/`. To build and run tests:

```bash
git clone <this-repo>
cd client-zig
zig build test
```

### Regenerate Protobuf Bindings (optional)
If you need to regenerate kvproto bindings from `third_party/_kvproto_src/`:

```bash
# Install protoc and git (macOS example)
brew install protobuf git

# Generate Zig protobuf files
zig build gen-proto

# See KVPROTO_SETUP.md for complete details
```

**📖 For detailed setup instructions, see [KVPROTO_SETUP.md](KVPROTO_SETUP.md)**

## Installation

Add this to your `build.zig.zon`:

```zig
.dependencies = .{
    .tikv_client = .{
        .url = "https://github.com/your-org/tikv-client-zig/archive/main.tar.gz",
        .hash = "...",
    },
},
```

## Quick Start

```zig
const std = @import("std");
const tikv = @import("tikv_client");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Connect to TiKV cluster
    const client = try tikv.Client.init(allocator, .{
        .pd_endpoints = &.{"127.0.0.1:2379"},
    });
    defer client.deinit();

    // Raw KV operations
    try client.put("key1", "value1");
    const value = try client.get("key1");
    std.debug.print("Got value: {s}\n", .{value.?});

    // Transactional operations
    const txn = try client.begin();
    try txn.put("key2", "value2");
    try txn.commit();
}
```

## Architecture

This client uses:
- **kvproto** (release-7.1) for TiKV protocol definitions
- **zig-protobuf** for Zig-native protobuf code generation
- **Zig 0.15.1** standard library and allocators

## Testing

```bash
# Run all tests
zig build test

# Run module test aggregates
zig build test
```

## Documentation

- [kvproto Setup Guide](KVPROTO_SETUP.md) - Complete protobuf binding setup
- [API Reference](docs/api.md)
- [Examples](examples/)
- [Contributing](CONTRIBUTING.md)

## License

Apache License 2.0


BatchCommands streaming.
TLS + ALPN.
Add TLS + ALPN(h2) Support

Enable HTTPS connections to PD
Proper HTTP/2 over TLS with ALPN negotiation
Support for production PD deployments with TLS

Expand gRPC Client

Add streaming RPC support (server/client/bidirectional streaming)
Add more PD API methods (GetRegion, GetStore, etc.)
Add TiKV client methods