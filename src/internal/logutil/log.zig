// internal/logutil/log.zig
// Lightweight logger facade. Mirrors Go API shape: BgLogger() and Logger(ctx).
// Uses logz for consistency across the codebase.

const std = @import("std");
// Mock logz for testing environment
pub const logz = if (@import("builtin").is_test) struct {
    pub fn err() MockLogger {
        return MockLogger{};
    }
    pub fn info() MockLogger {
        return MockLogger{};
    }
    const MockLogger = struct {
        pub fn ctx(self: MockLogger, _: []const u8) MockLogger {
            return self;
        }
        pub fn int(self: MockLogger, _: []const u8, _: anytype) MockLogger {
            return self;
        }
        pub fn string(self: MockLogger, _: []const u8, _: []const u8) MockLogger {
            return self;
        }
        pub fn boolean(self: MockLogger, _: []const u8, _: bool) MockLogger {
            return self;
        }
        pub fn err(self: MockLogger, _: anyerror) MockLogger {
            return self;
        }
        pub fn log(self: MockLogger, _: []const u8) void {
            _ = self;
        }
    };
} else @import("logz");

pub const Logger = struct {
    scope: []const u8 = "tikv",

    pub fn debug(self: *const Logger, msg: []const u8, kv: anytype) void {
        _ = self;
        _ = kv;
        logz.debug().log(msg);
    }
    pub fn info(self: *const Logger, msg: []const u8, kv: anytype) void {
        _ = self;
        _ = kv;
        logz.info().log(msg);
    }
    pub fn warn(self: *const Logger, msg: []const u8, kv: anytype) void {
        _ = self;
        _ = kv;
        logz.warn().log(msg);
    }
    pub fn err(self: *const Logger, msg: []const u8, kv: anytype) void {
        _ = self;
        _ = kv;
        logz.err().log(msg);
    }
};

var bg = Logger{};

/// BgLogger returns the default global logger.
pub fn BgLogger() *const Logger {
    return &bg;
}

/// Logger gets a contextual logger from current context. Currently same as Bg.
pub fn LoggerFromCtx(_: ?*anyopaque) *const Logger {
    return &bg;
}

// Keep exported names similar to Go for convenience
pub const LoggerCtx = LoggerFromCtx;

test "bg logger prints without crash" {
    const lg = BgLogger();
    lg.debug("backoff", .{});
}
