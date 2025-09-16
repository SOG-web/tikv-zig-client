# TiKV Client-Zig: kvproto UPB Setup Guide

This document explains how to set up kvproto protobuf bindings using Google's UPB (μpb) library for the TiKV client-zig project.

## Overview

The TiKV client uses kvproto (TiKV's protobuf definitions) to communicate with TiKV servers. This project generates C bindings using UPB and exposes them to Zig via `@cImport`.

## Prerequisites

### Required Tools
- **Zig 0.15.1+** - For building the project
- **Protocol Buffers Compiler (protoc)** - For generating code from .proto files
- **Bazel** - For building UPB protoc plugins
- **Git** - For cloning dependencies
- **Homebrew** (macOS) or equivalent package manager

### Install Dependencies

```bash
# macOS with Homebrew
brew install protobuf bazel git

# Verify installations
protoc --version    # Should show libprotoc 3.x+
bazel --version     # Should show bazel 6.x+
zig version         # Should show 0.15.1+
```

## Project Structure

```
client-zig/
├── third_party/
│   ├── _kvproto_src/          # kvproto source (release-7.1)
│   ├── _protobuf_src/         # protobuf source for UPB plugins
│   └── kvproto-upb/           # Generated UPB bindings
│       ├── bin/               # UPB protoc plugin
│       ├── gen/               # Generated C headers/sources
│       └── upb/               # UPB runtime library
├── scripts/
│   └── gen_kvproto_upb.sh     # Code generation script
└── src/
    └── kvproto/               # Zig test files
```

## Setup Steps

### 1. Clone Dependencies

```bash
# From project root
git clone --depth 1 --branch release-7.1 \
  git@github.com:pingcap/kvproto.git third_party/_kvproto_src

git clone --depth 1 --branch v29.2 \
  https://github.com/protocolbuffers/protobuf.git third_party/_protobuf_src
```

### 2. Build UPB Protoc Plugin

```bash
# Build the main UPB plugin
cd third_party/_protobuf_src
bazel build //upb_generator:protoc-gen-upb
cp bazel-bin/upb_generator/protoc-gen-upb \
  ../kvproto-upb/bin/protoc-gen-upb

# Build the minitable plugin (for optimized runtime)
bazel build //upb_generator/minitable:protoc-gen-upb_minitable
# Note: Keep this in bazel-bin for the generator script
cd ../..
```

### 3. Vendor UPB Runtime

```bash
# Copy UPB runtime sources
mkdir -p third_party/kvproto-upb/upb
cp -r third_party/_protobuf_src/upb/* third_party/kvproto-upb/upb/
```

### 4. Generate kvproto UPB Bindings

```bash
# Run the generation script
./scripts/gen_kvproto_upb.sh \
  --kvproto third_party/_kvproto_src \
  --plugin "$(pwd)/third_party/kvproto-upb/bin/protoc-gen-upb" \
  --plugin-minitable "$(pwd)/third_party/_protobuf_src/bazel-bin/upb_generator/minitable/protoc-gen-upb_minitable" \
  --wkt "$(brew --prefix)/include"
```

This generates:
- `third_party/kvproto-upb/gen/*.upb.h` - Header files
- `third_party/kvproto-upb/gen/*.upb.c` - Implementation files  
- `third_party/kvproto-upb/gen/*.upb_minitable.h` - Minitable headers
- `third_party/kvproto-upb/gen/*.upb_minitable.c` - Minitable implementations

### 5. Build and Test

```bash
# Build the project
zig build

# Run tests (includes kvproto binding tests)
zig build test
```

## Generated Files

The generation process creates several key files:

### Core kvproto Messages
- `kvrpcpb.upb.h` - Main TiKV RPC definitions (Get, Put, Scan, etc.)
- `errorpb.upb.h` - Error handling types
- `metapb.upb.h` - Metadata types

### Dependencies  
- `eraftpb.upb_minitable.h` - Raft protocol definitions
- `google/api/annotations.upb_minitable.h` - Google API annotations

### UPB Runtime
- `upb/mem/arena.h` - Memory arena allocator
- `upb/base/string_view.h` - String handling utilities

## Usage in Zig

```zig
const std = @import("std");
const c = @cImport({
    @cInclude("kvrpcpb.upb.h");
    @cInclude("upb/mem/arena.h");
    @cInclude("upb/base/string_view.h");
});

test "kvproto basic usage" {
    // Create arena for memory management
    const arena = c.upb_Arena_New();
    defer c.upb_Arena_Free(arena);

    // Create a GetRequest
    const req = c.kvrpcpb_GetRequest_new(arena);
    
    // Set key field
    const key = "my-key";
    const sv = c.upb_StringView{ 
        .data = @as([*]const u8, @ptrCast(key.ptr)), 
        .size = key.len 
    };
    c.kvrpcpb_GetRequest_set_key(req, sv);

    // Serialize to bytes
    var len: usize = 0;
    const bytes = c.kvrpcpb_GetRequest_serialize(req, arena, &len);
    
    // Parse back from bytes
    const parsed = c.kvrpcpb_GetRequest_parse(
        @as([*]const u8, @ptrCast(bytes)), len, arena
    );
    
    // Verify round-trip
    const got_key = c.kvrpcpb_GetRequest_key(parsed);
    try std.testing.expectEqualStrings(key, got_key.data[0..got_key.size]);
}
```

## Troubleshooting

### Common Issues

**"No such file or directory" during generation**
- Ensure all paths in the generation command are absolute
- Check that `third_party/kvproto-upb/gen` directory exists
- Verify protoc plugins are executable

**"eraftpb.upb_minitable.h not found"**
- Make sure the generation script includes `--plugin-minitable`
- Verify that include protos are being processed (eraftpb.proto, etc.)

**Zig compilation errors with @ptrCast**
- Use Zig 0.15+ syntax: `@as(DestType, @ptrCast(value))`
- Not the old syntax: `@ptrCast(DestType, value)`

**Missing UPB symbols**
- Ensure UPB runtime is properly vendored in `third_party/kvproto-upb/upb/`
- Check that build.zig includes all necessary UPB source files

### Regeneration

To regenerate bindings (e.g., after kvproto updates):

```bash
# Clean existing generated files
rm -rf third_party/kvproto-upb/gen/*

# Re-run generation
./scripts/gen_kvproto_upb.sh \
  --kvproto third_party/_kvproto_src \
  --plugin "$(pwd)/third_party/kvproto-upb/bin/protoc-gen-upb" \
  --plugin-minitable "$(pwd)/third_party/_protobuf_src/bazel-bin/upb_generator/minitable/protoc-gen-upb_minitable" \
  --wkt "$(brew --prefix)/include"
```

## Architecture Notes

### Why UPB?
- **Performance**: UPB generates smaller, faster code than other protobuf libraries
- **C Compatibility**: Works seamlessly with Zig's `@cImport`
- **Memory Efficiency**: Arena-based allocation reduces fragmentation
- **Minimal Dependencies**: Self-contained runtime

### Generated Code Structure
- **Message Types**: `kvrpcpb_GetRequest`, `kvrpcpb_GetResponse`, etc.
- **Constructors**: `*_new(arena)` functions
- **Accessors**: `*_get_field()` and `*_set_field()` functions  
- **Serialization**: `*_serialize()` and `*_parse()` functions
- **Minitable**: Optimized reflection data for smaller binaries

### Memory Management
- All protobuf objects are allocated from UPB arenas
- Arena cleanup automatically frees all associated memory
- No individual object deallocation needed
- Thread-safe arena reference counting available

## Performance Considerations

- Use minitable headers when possible for smaller binary size
- Reuse arenas for multiple related operations
- Consider arena size hints for large message batches
- Profile memory usage in long-running applications

## Version Compatibility

- **kvproto**: release-7.1 (matches TiKV 7.1.x)
- **protobuf**: v29.2 (for UPB generator)
- **Zig**: 0.15.1+ (for modern @ptrCast syntax)

For updates, check compatibility between kvproto versions and your target TiKV cluster.
