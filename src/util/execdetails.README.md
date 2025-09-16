# util/execdetails.zig

Execution detail data structures and helpers, ported from `client-go/util/execdetails.go`.
These structs carry per-request/per-transaction timings and counters, and provide formatting helpers for logs.

## Types
- `ExecDetails`
  - `backoff_count: i64`
  - `backoff_duration_ns: i64`
  - `wait_kv_resp_duration_ns: i64`
  - `wait_pd_resp_duration_ns: i64`

- `CommitDetails`
  - Tracks timings for commit phases and write metrics.
  - `merge(other)` and `clone()` methods.

- `LockKeysDetails`
  - Tracks lock-key RPC metrics. `merge(other)` and `clone()` methods.

- `ScanDetail`
  - Accumulates scan metrics. `merge(other)` and `formatAlloc(allocator)` which returns a human-readable string (or empty) mirroring Go.

- `TimeDetail`
  - `process_time_ns`, `wait_time_ns`, `kv_read_wall_time_ms`
  - `formatAlloc(allocator)` returns a readable string like: `total_process_time: 10.4ms, total_wait_time: 2s`.
  - `mergeFromPBMillis(wait_ms, process_ms, kv_read_ms)` to integrate protobuf millisecond fields.

## Notes
- Durations are handled as nanoseconds for precision, and printed via `util/misc.zig`'s `formatDurationAlloc`.
- This module only defines data containers and formatting utilities; integrating with a future PD client wrapper (like Go's `pd_interceptor`) will happen in a higher-level module.
