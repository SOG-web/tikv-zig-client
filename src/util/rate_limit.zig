const std = @import("std");

// RateLimit provides a concurrency limiter similar to Go's util.RateLimit.
// It uses a mutex + condition variable to implement a counting semaphore.
pub const RateLimit = struct {
    capacity: usize,
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    in_use: usize = 0,

    pub fn init(n: usize) RateLimit {
        return .{ .capacity = n };
    }

    // acquire blocks until a token is available.
    pub fn acquire(self: *RateLimit) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        while (self.in_use >= self.capacity) {
            self.cond.wait(&self.mutex);
        }
        self.in_use += 1;
    }

    // tryAcquire attempts to acquire without blocking.
    // Returns true if acquired, false otherwise.
    pub fn tryAcquire(self: *RateLimit) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.in_use >= self.capacity) return false;
        self.in_use += 1;
        return true;
    }

    // release returns a token to the pool.
    pub fn release(self: *RateLimit) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.in_use == 0) @panic("release called with no outstanding token");
        self.in_use -= 1;
        self.cond.signal();
    }

    pub fn getCapacity(self: *RateLimit) usize {
        return self.capacity;
    }
};

// ---- tests ----

test "rate_limit basic" {
    var rl = RateLimit.init(2);
    try std.testing.expectEqual(@as(usize, 2), rl.getCapacity());
    try std.testing.expect(rl.tryAcquire());
    try std.testing.expect(rl.tryAcquire());
    try std.testing.expect(!rl.tryAcquire());
    rl.release();
    try std.testing.expect(rl.tryAcquire());
}
