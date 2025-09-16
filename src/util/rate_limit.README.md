# util/rate_limit.zig

A simple concurrency limiter (counting semaphore) analogous to Go's `util.RateLimit`.

## What it does
- Provides a fixed-capacity limiter to throttle concurrent operations.
- API:
  - `RateLimit.init(n: usize) RateLimit` — create with capacity `n`.
  - `acquire()` — blocks until a token is available.
  - `tryAcquire() -> bool` — non-blocking attempt.
  - `release()` — returns a token.
  - `getCapacity() -> usize` — returns capacity.

## Usage
```zig
var rl = RateLimit.init(8);
if (!rl.tryAcquire()) {
    // queue or backoff
} else {
    defer rl.release();
    // do work
}
```

## Notes
- Uses `std.Thread.Mutex` and `std.Thread.Condition` under Zig 0.15.1.
- Panics on `release()` if no token is currently held to surface misuse.
