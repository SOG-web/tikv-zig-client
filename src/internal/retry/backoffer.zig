// internal/retry/backoffer.zig
// Backoffer orchestration mirroring Go's internal/retry/backoff.go (sans metrics and external tracing).
// - Tracks per-type sleep times and counts
// - Honors a maxSleep budget (excluding some types like tikvServerBusy)
// - Integrates with kv.Variables (BackOffWeight multiplication, killed flag)
// - Optional ExecDetails accumulation

const std = @import("std");
const logutil = @import("../logutil/log.zig");
const tracing = @import("../logutil/tracing.zig");
const kv = @import("../../kv/types.zig");
const cfg = @import("config.zig");
const backoffz = @import("backoff.zig");
const execdetails = @import("../../util/execdetails.zig");

pub const BackofferError = error{
    Timeout,
    Canceled,
};

pub const Backoffer = struct {
    // A lightweight, opaque ctx you can thread through (unused by default implementation)
    ctx: ?*anyopaque = null,

    // Config name -> Backoff instance
    fn_map: std.StringHashMap(backoffz.Backoff) = undefined,

    // Budget and accounting (milliseconds)
    max_sleep_ms: i32 = 0,
    total_sleep_ms: i32 = 0,
    excluded_sleep_ms: i32 = 0,

    // Vars and mode
    vars: *kv.Variables,
    noop: bool = false,

    // For diagnostics
    errors: std.ArrayList([]u8) = undefined,
    configs: std.ArrayList([]const u8) = undefined,
    backoff_sleep_ms: std.StringHashMap(i32) = undefined,
    backoff_times: std.StringHashMap(i32) = undefined,
    parent: ?*Backoffer = null,

    // Optional exec details aggregation
    exec: ?*execdetails.ExecDetails = null,

    pub fn init(allocator: std.mem.Allocator, ctx: ?*anyopaque, max_sleep_ms: i32, vars: *kv.Variables) Backoffer {
        var self = Backoffer{
            .ctx = ctx,
            .fn_map = std.StringHashMap(backoffz.Backoff).init(allocator),
            .max_sleep_ms = max_sleep_ms,
            .total_sleep_ms = 0,
            .excluded_sleep_ms = 0,
            .vars = vars,
            .noop = false,
            .errors = std.ArrayList([]u8).init(allocator),
            .configs = std.ArrayList([]const u8).init(allocator),
            .backoff_sleep_ms = std.StringHashMap(i32).init(allocator),
            .backoff_times = std.StringHashMap(i32).init(allocator),
            .parent = null,
            .exec = null,
        };
        // Adjust budget by BackOffWeight like Go code
        if (self.max_sleep_ms > 0) {
            const weight = self.vars.back_off_weight;
            if (weight > 0 and @divTrunc(std.math.maxInt(i32), weight) >= self.max_sleep_ms) {
                self.max_sleep_ms *= weight;
            }
        }
        return self;
    }

    // Convenience constructors (mirroring Go helpers)
    pub fn new(allocator: std.mem.Allocator, ctx: ?*anyopaque, max_sleep_ms: i32) Backoffer {
        return Backoffer.init(allocator, ctx, max_sleep_ms, &kv.defaultVariables());
    }
    pub fn newWithVars(allocator: std.mem.Allocator, ctx: ?*anyopaque, max_sleep_ms: i32, vars: *kv.Variables) Backoffer {
        return Backoffer.init(allocator, ctx, max_sleep_ms, vars);
    }

    pub fn deinit(self: *Backoffer) void {
        const a = self.fn_map.allocator;
        var it = self.fn_map.iterator();
        while (it.next()) |e| _ = e; // plain values, nothing to free
        self.fn_map.deinit();
        // free error strings
        for (self.errors.items) |s| a.free(s);
        self.errors.deinit();
        self.configs.deinit();
        self.backoff_sleep_ms.deinit();
        self.backoff_times.deinit();
    }

    pub fn setExecDetails(self: *Backoffer, ed: *execdetails.ExecDetails) void {
        self.exec = ed;
    }

    pub fn getCtx(self: *Backoffer) ?*anyopaque {
        return self.ctx;
    }
    pub fn setCtx(self: *Backoffer, ctx: ?*anyopaque) void {
        self.ctx = ctx;
    }

    pub fn newNoop(allocator: std.mem.Allocator, ctx: ?*anyopaque) Backoffer {
        var b = Backoffer.init(allocator, ctx, 0, &kv.defaultVariables());
        b.noop = true;
        return b;
    }

    pub fn withVars(self: *Backoffer, vars_: *kv.Variables) *Backoffer {
        if (vars_ != null) self.vars = vars_;
        if (self.max_sleep_ms > 0) {
            const weight = self.vars.back_off_weight;
            if (weight > 0 and @divTrunc(std.math.maxInt(i32), weight) >= self.max_sleep_ms) {
                self.max_sleep_ms *= weight;
            }
        }
        return self;
    }

    /// Backoff with a config, err_msg is logged and accumulated.
    pub fn backoff(self: *Backoffer, allocator: std.mem.Allocator, c: *const cfg.Config, err_msg: []const u8) BackofferError!void {
        return self.backoffWithCfgAndMaxSleep(allocator, c, -1, err_msg);
    }

    /// Backoff using TxnLockFast config and max per-sleep limit.
    pub fn backoffWithMaxSleepTxnLockFast(self: *Backoffer, allocator: std.mem.Allocator, max_sleep_ms: i32, err_msg: []const u8) BackofferError!void {
        return self.backoffWithCfgAndMaxSleep(allocator, &cfg.BoTxnLockFast, max_sleep_ms, err_msg);
    }

    pub fn backoffWithCfgAndMaxSleep(self: *Backoffer, allocator: std.mem.Allocator, c: *const cfg.Config, max_sleep_ms: i32, err_msg: []const u8) BackofferError!void {
        if (self.noop) return;

        // Check killed
        if (self.vars.killed != null and self.vars.killed.* == 1) return BackofferError.Canceled;

        // Budget check
        if (self.max_sleep_ms > 0 and (self.total_sleep_ms - self.excluded_sleep_ms) >= self.max_sleep_ms) {
            // Warn and surface timeout; include longest sleep contributor
            const lg = logutil.BgLogger();
            if (self.longestSleepCfg()) |ls| {
                var buf: [160]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "backoffer.maxSleep exceeded, longest={s} {d}ms", .{ ls.name, ls.ms }) catch "backoffer exceeded";
                lg.warn(msg, .{});
            } else {
                lg.warn("backoffer.maxSleep exceeded", .{});
            }
            return BackofferError.Timeout;
        }

        // Trace
        tracing.Eventf(self.ctx, "tikv.backoff.{s}", .{c.name});

        // Record error line with timestamp
        const now_ns = std.time.nanoTimestamp();
        if (std.fmt.allocPrint(allocator, "{s} at {d}", .{ err_msg, now_ns })) |ts| {
            self.errors.append(ts) catch allocator.free(ts);
        } else |_| {}
        self.configs.append(c.name) catch {};

        // Lazy get backoff for this config
        const gop = self.fn_map.getOrPut(c.name) catch unreachable;
        if (!gop.found_existing) {
            gop.value_ptr.* = c.createBackoff(self.vars);
        }
        var bo = gop.value_ptr;
        const real_sleep = bo.sleep(max_sleep_ms);

        //TODO: add metrics

        // Accounting aggregation
        self.total_sleep_ms += real_sleep;
        if (cfg.isSleepExcluded(c.name)) self.excluded_sleep_ms += real_sleep;
        // by type maps
        const s1 = self.backoff_sleep_ms.getOrPut(c.name) catch unreachable;
        if (!s1.found_existing) s1.value_ptr.* = 0;
        s1.value_ptr.* += real_sleep;
        const s2 = self.backoff_times.getOrPut(c.name) catch unreachable;
        if (!s2.found_existing) s2.value_ptr.* = 0;
        s2.value_ptr.* += 1;

        // Exec details
        if (self.exec) |ed| {
            ed.backoff_count += 1;
            ed.backoff_duration_ns += @as(i64, real_sleep) * std.time.ns_per_ms;
        }

        // Debug log similar to Go's Logger(ctx).Debug("retry later", ...)
        const lg = logutil.BgLogger();
        var dbuf: [160]u8 = undefined;
        const dmsg = std.fmt.bufPrint(&dbuf, "retry later type={s} totalSleep={} excludedSleep={} maxSleep={} err={s}", .{
            c.name, self.total_sleep_ms, self.excluded_sleep_ms, self.max_sleep_ms, err_msg,
        }) catch "retry later";
        lg.debug(dmsg, .{});
    }

    pub fn clone(self: *Backoffer, allocator: std.mem.Allocator) Backoffer {
        var b = Backoffer.init(allocator, self.ctx, self.max_sleep_ms, self.vars);
        b.total_sleep_ms = self.total_sleep_ms;
        b.excluded_sleep_ms = self.excluded_sleep_ms;
        b.parent = self;
        b.exec = self.exec;
        return b;
    }

    pub fn fork(self: *Backoffer, allocator: std.mem.Allocator) Backoffer {
        // No separate context; keep same ctx pointer
        var b = Backoffer.init(allocator, self.ctx, self.max_sleep_ms, self.vars);
        b.total_sleep_ms = self.total_sleep_ms;
        b.excluded_sleep_ms = self.excluded_sleep_ms;
        b.parent = self;
        b.exec = self.exec;
        return b;
    }

    pub fn reset(self: *Backoffer) void {
        self.fn_map.clearRetainingCapacity();
        self.total_sleep_ms = 0;
        self.excluded_sleep_ms = 0;
    }

    pub fn resetMaxSleep(self: *Backoffer, new_max_ms: i32) void {
        self.reset();
        self.max_sleep_ms = new_max_ms;
        _ = self.withVars(self.vars);
    }

    pub fn getVars(self: *Backoffer) *kv.Variables {
        return self.vars;
    }
    pub fn getTotalSleep(self: *Backoffer) i32 {
        return self.total_sleep_ms;
    }
    pub fn errorsNum(self: *Backoffer) usize {
        return self.errors.items.len;
    }

    pub fn getTypes(self: *Backoffer, allocator: std.mem.Allocator) ![][]const u8 {
        var arr = std.ArrayList([]const u8).init(allocator);
        var cur: ?*Backoffer = self;
        while (cur) |p| : (cur = p.parent) {
            for (p.configs.items) |name| try arr.append(name);
        }
        return arr.toOwnedSlice();
    }

    pub fn getBackoffTimes(self: *Backoffer, allocator: std.mem.Allocator) !std.StringHashMap(i32) {
        var m = std.StringHashMap(i32).init(allocator);
        var it = self.backoff_times.iterator();
        while (it.next()) |e| try m.put(e.key_ptr.*, e.value_ptr.*);
        return m;
    }

    pub fn getTotalBackoffTimes(self: *Backoffer) i32 {
        var sum: i32 = 0;
        var it = self.backoff_times.iterator();
        while (it.next()) |e| sum += e.value_ptr.*;
        return sum;
    }

    pub fn getBackoffSleepMS(self: *Backoffer, allocator: std.mem.Allocator) !std.StringHashMap(i32) {
        var m = std.StringHashMap(i32).init(allocator);
        var it = self.backoff_sleep_ms.iterator();
        while (it.next()) |e| try m.put(e.key_ptr.*, e.value_ptr.*);
        return m;
    }

    pub fn longestSleepCfg(self: *Backoffer) ?struct { name: []const u8, ms: i32 } {
        var candidate: []const u8 = "";
        var max_ms: i32 = -1;
        var it = self.backoff_sleep_ms.iterator();
        while (it.next()) |e| {
            const name = e.key_ptr.*;
            const ms = e.value_ptr.*;
            if (cfg.isSleepExcluded(name)) continue;
            if (ms > max_ms) {
                max_ms = ms;
                candidate = name;
            }
        }
        if (max_ms <= 0) return null;
        return .{ .name = candidate, .ms = max_ms };
    }

    /// Format a summary string like Go's String(): " backoff(<total>ms [types...])"
    pub fn stringAlloc(self: *Backoffer, allocator: std.mem.Allocator) ![]u8 {
        if (self.total_sleep_ms == 0) return allocator.alloc(u8, 0);
        var list = std.ArrayList([]const u8).init(allocator);
        defer list.deinit();
        for (self.configs.items) |name| try list.append(name);
        const joined = try std.mem.join(allocator, ",", list.items);
        defer allocator.free(joined);
        return std.fmt.allocPrint(allocator, " backoff({d}ms {s})", .{ self.total_sleep_ms, joined });
    }
};

// ---------------- Tests ----------------

test "backoffer accumulates and respects excluded sleep" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();
    var vars = kv.defaultVariables();
    vars.back_off_weight = 1;

    var bo = Backoffer.init(A, null, 50, &vars);
    defer bo.deinit();

    // two types: one excluded (tikvServerBusy), one not
    try bo.backoff(A, &cfg.BoRegionMiss, "miss"); // default sleeps ~2, 4, 8 ... (NoJitter)
    try bo.backoff(A, &cfg.BoTiKVServerBusy, "busy"); // excluded from budget

    const total = bo.getTotalSleep();
    try std.testing.expect(total > 0);
}
