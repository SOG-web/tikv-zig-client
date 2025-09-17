const std = @import("std");
const common = @import("common.zig");
const pdpb = common.pdpb;
const logz = common.logz;

pub const PDError = struct {
    err: *pdpb.Error,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, err: *pdpb.Error) PDError {
        return PDError{ .err = err, .allocator = allocator };
    }

    pub fn format(self: PDError, writer: anytype) !void {
        const error_type = self.err.type;
        const msg_str = self.err.message;
        try writer.print("pd error(type: {}, message: {s})", .{ error_type, msg_str });
    }

    pub fn error_string(self: PDError, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{self});
    }

    pub fn format_to_buffer(self: PDError, buf: []u8) ![]u8 {
        const error_type = self.err.type;
        const msg_str = self.err.message;
        return std.fmt.bufPrint(buf, "pd error(type: {}, message: {s})", .{ error_type, msg_str });
    }

    pub fn log_error(self: PDError) void {
        const error_type = self.err.type;
        const msg_str = self.err.message;
        logz.err().ctx("PDError").int("type", @intFromEnum(error_type)).string("message", msg_str).log("PD error occurred");
    }
};
