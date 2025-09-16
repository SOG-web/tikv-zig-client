# util/misc.zig

Utilities for formatting bytes and durations and for ASCII uppercase conversion and hex encoding.
Port of selected helpers from `client-go/util/misc.go` to keep logs and metrics formatting consistent.

## What it does
- **formatBytesAlloc(allocator, num_bytes: i64) -> []u8**
  - Human-friendly sizes (Bytes, KB, MB, GB) with pruned precision, compatible with Go's `FormatBytes` behavior.
- **bytesToStringAlloc(allocator, num_bytes: i64) -> []u8**
  - Alternate formatting (e.g., `1.23 KB`) used when size is below thresholds.
- **formatDurationAlloc(allocator, ns: i64) -> []u8**
  - Duration formatting with precision pruning similar to Go's `FormatDuration`.
  - Chooses among ns, µs, ms, s; uses 0/1/2 decimals depending on magnitude/divisibility.
- **toUpperASCIIInplace(buf: []u8) -> void**
  - In-place ASCII uppercase without allocation.
- **encodeToHexUpperAlloc(allocator, src: []const u8) -> []u8**
  - Uppercase hex encoding (no `0x` prefix).
- **hexRegionKeyAlloc(allocator, key: []const u8) -> []u8**, **hexRegionKeyStrAlloc(...)**
  - Convenience wrappers for log-friendly hex region keys.

## Usage
```zig
const misc = @import("client_zig").util.misc;
const s = try misc.formatBytesAlloc(gpa, 1_572_864); // "1.5 MB"
```

## Zig 0.15.1 notes
- All functions that allocate return owned `[]u8` using the provided allocator.
- No reliance on deprecated APIs.
