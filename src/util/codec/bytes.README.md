# util/codec/bytes.zig

Mem-comparable byte-slice encoding and decoding ported from TiKV/TiDB (`client-go/util/codec/bytes.go`). Strict, byte-for-byte compatible with Go.

## What it does
- Encodes arbitrary byte slices into a sequence that preserves lexicographic ordering under raw byte comparison.
- Format is groups of 8 bytes padded with 0x00, followed by a 1-byte marker `0xFF - pad_count`.
- Decodes the format back to the original bytes, validating padding bytes.

Reference: MyRocks memcomparable format: https://github.com/facebook/mysql-5.6/wiki/MyRocks-record-format#memcomparable-format

## Public API
- `encodeBytes(allocator, data) -> []u8`
  - Allocates and returns the mem-comparable encoding of `data`.
- `encodeBytesAppend(dst: *std.ArrayList(u8), allocator, data) -> !void`
  - Appends the encoding to `dst` (high-performance, no intermediate allocs).
- `decodeBytes(allocator, input, buf_opt) -> { rest: []const u8, decoded: []u8 }`
  - Decodes from `input`, returning leftovers and an owned `decoded`. If `buf_opt` is provided, it reuses that `ArrayList(u8)` to minimize allocations.

## Usage examples
```zig
const std = @import("std");
const bytes = @import("./bytes.zig");

pub fn example(gpa: std.mem.Allocator) !void {
    // Allocate-and-return API
    const enc = try bytes.encodeBytes(gpa, "abc");
    defer gpa.free(enc);

    const res = try bytes.decodeBytes(gpa, enc, null);
    defer gpa.free(res.decoded);
    std.debug.assert(std.mem.eql(u8, res.decoded, "abc"));

    // Append API
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);
    try bytes.encodeBytesAppend(&buf, gpa, "xyz");
    // buf.items now contains the encoding
}
```

## Zig 0.15.1 notes
- Uses `std.ArrayList` unmanaged form with explicit `allocator` arguments (`append`, `appendSlice`, `toOwnedSlice(allocator)`, `deinit(allocator)`).
- Avoids deprecated `usingnamespace` and old writer/print APIs.

## Performance
- Pre-reserves capacity with `ensureUnusedCapacity` using an upper bound `((len/8)+1)*(8+1)` to minimize reallocations.
- Append-style API avoids temporary heap allocations when composing keys.
