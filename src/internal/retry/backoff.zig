// internal/retry/backoff.zig
// Exponential backoff state machine and jitter policies.

const std = @import("std");
const logutil = @import("../logutil/log.zig");

pub const Jitter = enum(u8) {
    NoJitter = 1,
    FullJitter,
    EqualJitter,
    DecorrJitter,
};

fn expo(base: i32, cap: i32, n: i32) i32 {
    const pow = std.math.powi(i32, 2, n) catch std.math.maxInt(i32);
    const v = base * pow;
    return if (v < cap) v else cap;
}
