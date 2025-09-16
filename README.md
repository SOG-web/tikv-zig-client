# !!!!This library is not ready for use, it still in development. No build or Test are currently passing

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
For most users, the generated protobuf bindings are already included. Simply:

```bash
git clone <this-repo>
cd client-zig
zig build test
```

### Full Setup (Regenerating Protobuf Bindings)
If you need to regenerate kvproto bindings or set up from scratch:

```bash
# Install dependencies
brew install protobuf bazel git  # macOS

# See KVPROTO_SETUP.md for complete setup instructions
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
- **UPB (μpb)** for high-performance protobuf serialization
- **Zig's @cImport** for seamless C interop
- **Arena-based memory management** for efficient allocation

## Testing

```bash
# Run all tests
zig build test

# Test kvproto bindings specifically
zig test src/kvproto/header_sanity_test.zig
zig test src/kvproto/roundtrip_test.zig
```

## Documentation

- [kvproto Setup Guide](KVPROTO_SETUP.md) - Complete protobuf binding setup
- [API Reference](docs/api.md)
- [Examples](examples/)
- [Contributing](CONTRIBUTING.md)

## License

Apache License 2.0


