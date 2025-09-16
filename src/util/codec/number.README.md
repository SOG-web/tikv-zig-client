# util/codec/number.zig

Encoding/decoding utilities for integers, ported from `client-go/util/codec/number.go` with strict byte-level compatibility.

## What it does
- __Comparable fixed-width__: 64-bit signed/unsigned integers in big-endian encodings that preserve numeric ordering under bytewise compare.
  - `encodeIntToCmpUint` and `decodeCmpUintToInt`
  - `encodeInt{,Desc}{,Append}` / `decodeInt{,Desc}`
  - `encodeUint{,Desc}{,Append}` / `decodeUint{,Desc}`
- __Standard varints__: Go-compatible Uvarint/Varint (LEB128 with ZigZag for signed).
  - `encodeUvarint{,Append}` / `decodeUvarint`
  - `encodeVarint{,Append}` / `decodeVarint`
- __Comparable varints__: Mem-comparable tag-length big-endian encodings used by TiDB/TiKV.
  - `encodeComparableUvarint{,Append}` / `decodeComparableUvarint`
  - `encodeComparableVarint{,Append}` / `decodeComparableVarint`

## Public API overview
```zig
// Fixed width comparable
pub fn encodeIntToCmpUint(v: i64) u64
pub fn decodeCmpUintToInt(u: u64) i64
pub fn encodeIntAppend(dst: *std.ArrayList(u8), allocator: std.mem.Allocator, v: i64) !void
pub fn encodeInt(allocator: std.mem.Allocator, v: i64) ![]u8
pub fn encodeIntDescAppend(dst: *std.ArrayList(u8), allocator: std.mem.Allocator, v: i64) !void
pub fn encodeIntDesc(allocator: std.mem.Allocator, v: i64) ![]u8
pub fn decodeInt(input: []const u8) DecodeError!DecodeIntResult
pub fn decodeIntDesc(input: []const u8) DecodeError!DecodeIntResult

pub fn encodeUintAppend(dst: *std.ArrayList(u8), allocator: std.mem.Allocator, v: u64) !void
pub fn encodeUint(allocator: std.mem.Allocator, v: u64) ![]u8
pub fn encodeUintDescAppend(dst: *std.ArrayList(u8), allocator: std.mem.Allocator, v: u64) !void
pub fn encodeUintDesc(allocator: std.mem.Allocator, v: u64) ![]u8
pub fn decodeUint(input: []const u8) DecodeError!DecodeUintResult
pub fn decodeUintDesc(input: []const u8) DecodeError!DecodeUintResult

// Varints (Go-compatible)
pub fn encodeUvarintAppend(dst: *std.ArrayList(u8), allocator: std.mem.Allocator, v: u64) !void
pub fn encodeUvarint(allocator: std.mem.Allocator, v: u64) ![]u8
pub fn decodeUvarint(input: []const u8) DecodeError!DecodeUvarintResult

pub fn encodeVarintAppend(dst: *std.ArrayList(u8), allocator: std.mem.Allocator, x: i64) !void
pub fn encodeVarint(allocator: std.mem.Allocator, x: i64) ![]u8
pub fn decodeVarint(input: []const u8) DecodeError!DecodeVarintResult

// Comparable varints
pub fn encodeComparableUvarintAppend(dst: *std.ArrayList(u8), allocator: std.mem.Allocator, v: u64) !void
pub fn encodeComparableUvarint(allocator: std.mem.Allocator, v: u64) ![]u8
pub fn decodeComparableUvarint(input: []const u8) DecodeError!DecodeUvarintResult

pub fn encodeComparableVarintAppend(dst: *std.ArrayList(u8), allocator: std.mem.Allocator, v: i64) !void
pub fn encodeComparableVarint(allocator: std.mem.Allocator, v: i64) ![]u8
pub fn decodeComparableVarint(input: []const u8) DecodeError!DecodeVarintResult
```

## Notes on compatibility
- The fixed-width comparable formats use big-endian and an XOR with `0x8000_0000_0000_0000` to make signed integers comparable as unsigned bytes.
- Varint encoding matches Go’s `encoding/binary` implementation (see `varint.go` in Go source). For signed, ZigZag transform is used to interleave negatives.
- Comparable varints follow TiDB/TiKV rules:
  - Negative: tag = `8 - length`, then big-endian bytes; smaller values use more bytes and sort first.
  - Positive: tag = `0xF7 + length`, then big-endian bytes; larger values use more bytes and sort later.
  - Single-byte range [0..239] uses `byte + 8` without additional bytes.

## Zig 0.15.1 notes
- `std.ArrayList` unmanaged is used. Pass allocators to `append`, `appendSlice`, and `toOwnedSlice(allocator)`; free with `deinit(allocator)`.
- `@bitCast` is single-argument and requires known result type; explicit intermediate variables are used where needed.

## Examples
```zig
const std = @import("std");
const number = @import("./number.zig");

pub fn example(gpa: std.mem.Allocator) !void {
    // Fixed-width comparable int
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);
    try number.encodeIntAppend(&buf, gpa, -123);
    const r = try number.decodeInt(buf.items);
    std.debug.assert(r.value == -123);

    // Go-compatible varint
    buf.clearRetainingCapacity();
    try number.encodeVarintAppend(&buf, gpa, -456);
    const rv = try number.decodeVarint(buf.items);
    std.debug.assert(rv.value == -456);

    // Comparable varint
    buf.clearRetainingCapacity();
    try number.encodeComparableVarintAppend(&buf, gpa, 123456);
    const rc = try number.decodeComparableVarint(buf.items);
    std.debug.assert(rc.value == 123456);
}
```
