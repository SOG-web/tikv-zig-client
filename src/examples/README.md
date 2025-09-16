# examples

This directory contains small, focused examples showing how to compose keys using the utilities in `util/codec/`.

## compose_keys.zig
Demonstrates building a lexicographically ordered key out of structured fields:
- `table_id` (u64, ascending)
- `user_key` (arbitrary bytes, mem-comparable encoding)
- `ts` (i64, descending so newer versions sort first)

Public API:
```zig
pub fn composeKey(allocator: std.mem.Allocator, table_id: u64, user_key: []const u8, ts: i64) ![]u8
```

Run its tests:
```sh
zig build test
```

In code, import via the package root:
```zig
const examples = @import("client_zig").examples;
const key = try examples.compose_keys.composeKey(gpa, 1, "abc", 42);
```
