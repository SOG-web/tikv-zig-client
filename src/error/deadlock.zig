const std = @import("std");
const common = @import("common.zig");
const kvrpcpb = common.kvrpcpb;
const logz = common.logz;

pub const ErrDeadlock = struct {
    deadlock: kvrpcpb.Deadlock,
    is_retryable: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, deadlock: kvrpcpb.Deadlock, is_retryable: bool) ErrDeadlock {
        return ErrDeadlock{
            .deadlock = deadlock,
            .is_retryable = is_retryable,
            .allocator = allocator,
        };
    }

    pub fn format(self: ErrDeadlock, writer: anytype) !void {
        const lock_ts = self.deadlock.lock_ts;
        const deadlock_key_hash = self.deadlock.deadlock_key_hash;
        const lock_key = self.deadlock.lock_key;
        const wait_chain_size: usize = self.deadlock.wait_chain.items.len;
        const lock_key_str = if (lock_key.len > 0) lock_key else "<empty>";
        try writer.print("deadlock(lock_ts: {}, key_hash: {}, lock_key: {s}, wait_chain_len: {}, retryable: {})", .{ lock_ts, deadlock_key_hash, lock_key_str, wait_chain_size, self.is_retryable });
    }

    pub fn error_string(self: ErrDeadlock, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    pub fn format_to_buffer(self: ErrDeadlock, buf: []u8) ![]u8 {
        const lock_ts = self.deadlock.lock_ts;
        const deadlock_key_hash = self.deadlock.deadlock_key_hash;
        const lock_key = self.deadlock.lock_key;
        const wait_chain_size: usize = self.deadlock.wait_chain.items.len;
        const lock_key_str = if (lock_key.len > 0) lock_key else "<empty>";
        return std.fmt.bufPrint(buf, "deadlock(lock_ts: {}, key_hash: {}, lock_key: {s}, wait_chain_len: {}, retryable: {})", .{ lock_ts, deadlock_key_hash, lock_key_str, wait_chain_size, self.is_retryable });
    }

    pub fn log_error(self: ErrDeadlock) void {
        const lock_ts = self.deadlock.lock_ts;
        const deadlock_key_hash = self.deadlock.deadlock_key_hash;
        const wait_chain_size: usize = self.deadlock.wait_chain.items.len;
        logz.err().ctx("Deadlock").int("lock_ts", lock_ts).int("key_hash", deadlock_key_hash).int("wait_chain_len", wait_chain_size).boolean("retryable", self.is_retryable).log("Deadlock detected");
    }
};
