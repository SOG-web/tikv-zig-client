// internal/logutil/tracing.zig
// Lightweight tracing facade inspired by Go's internal/logutil/tracing.go.
// Default is no-op; you can inject a custom tracer adapter.
// TODO: Fix tracing to work with opentelemetry.

const std = @import("std");

pub const Tracer = struct {
    ctx: ?*anyopaque = null,
    event: fn (ctx: ?*anyopaque, event: []const u8) void,
    setTag: fn (ctx: ?*anyopaque, key: []const u8, value: []const u8) void,
};

var g_tracer: ?Tracer = null;

pub fn setTracer(t: Tracer) void {
    g_tracer = t;
}

pub fn getTracer() ?Tracer {
    return g_tracer;
}

/// Record an event in the current tracing span (if any). No-op if no tracer set.
pub fn Event(ctx: ?*anyopaque, event: []const u8) void {
    if (g_tracer) |t| t.event(t.ctx orelse ctx, event);
}

/// Record a formatted event. Formats into a small local buffer to avoid allocations
/// when possible; falls back to heap allocate if needed.
pub fn Eventf(ctx: ?*anyopaque, comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    if (std.fmt.bufPrint(&buf, fmt, args)) |s| {
        return Event(ctx, s);
    } else |_| {
        // Fallback allocate
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const a = gpa.allocator();
        if (std.fmt.allocPrint(a, fmt, args)) |heap_s| {
            defer a.free(heap_s);
            Event(ctx, heap_s);
        } else |_| {
            // give up formatting
            Event(ctx, "trace_event_format_error");
        }
    }
}

/// Set a tag on the current tracing span (if any). No-op if no tracer set.
pub fn SetTag(ctx: ?*anyopaque, key: []const u8, value: []const u8) void {
    if (g_tracer) |t| t.setTag(t.ctx orelse ctx, key, value);
}

/// Built-in no-op tracer implementation
pub fn installNoopTracer() void {
    const noop = Tracer{
        .ctx = null,
        .event = struct {
            fn f(_: ?*anyopaque, _: []const u8) void {}
        }.f,
        .setTag = struct {
            fn f(_: ?*anyopaque, _: []const u8, _: []const u8) void {}
        }.f,
    };
    setTracer(noop);
}

test "tracing facade no-op does not crash" {
    installNoopTracer();
    Event(null, "hello");
    Eventf(null, "%s %d", .{ "world", 1 });
    SetTag(null, "k", "v");
}
