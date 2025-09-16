const std = @import("std");

// withRecovery mirrors Go's util.WithRecovery intent for goroutines/tasks:
// - Run exec()
// - If it returns an error, invoke recoverFn(err) if provided, then log the error
//   and (when available) the error return trace for easier debugging.
// Notes:
// - Zig has no panic-recovery; panics abort by default. Prefer returning errors.
// - To see error return traces, build tests or executables with error tracing enabled (default in tests).
pub fn withRecovery(exec: fn () anyerror!void, recoverFn: ?fn (err: anyerror) void) void {
    exec() catch |err| {
        if (recoverFn) |rf| rf(err);
        std.log.err("error in the recoverable task: {s}", .{@errorName(err)});
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
    };
}

// ---- tests ----

var g_called: bool = false;

test "withRecovery logs error and calls recoverFn" {
    g_called = false;
    const errfn = struct {
        fn f(err: anyerror) void {
            _ = err;
            g_called = true;
        }
    };
    const bad = struct {
        fn run() !void { return error.TestFailure; }
    };
    withRecovery(bad.run, errfn.f);
    try std.testing.expect(g_called);
}
