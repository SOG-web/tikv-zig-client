# util/ts_set.zig

Thread-safe set of timestamps (`u64`) with lazy initialization, ported from `client-go/util/ts_set.go`.

## What it does
- Lazily allocates the underlying map on first insert to avoid overhead in the common case (no conflicts).
- Provides read/write locking to allow concurrent reads with `RwLock`.

## API
- `TSSet.init() -> TSSet`
- `deinit(allocator)` — frees the internal map if allocated.
- `put(allocator, tss: []const u64) -> !void` — inserts one or more timestamps.
- `getAll(allocator) -> ![]u64` — returns a newly allocated slice of all timestamps (order unspecified).

## Notes
- Uses `std.AutoHashMap(u64, void)` for performance; capacity is reserved to `max(len(tss), 5)` on first allocation to match Go's small initial capacity.
