const std = @import("std");
const request_mod = @import("request.zig");

const RequestType = request_mod.RequestType;

pub const CallResult = struct {
    typ: RequestType,
    duration_ns: u64 = 0,

    pub fn start(typ: RequestType) CallResult {
        return .{ .typ = typ, .duration_ns = 0 };
    }

    pub fn finish(self: *CallResult, start_ns: i128) void {
        const end_ns = std.time.nanoTimestamp();
        const delta: i128 = end_ns - start_ns;
        const non_neg: i128 = if (delta < 0) 0 else delta;
        self.duration_ns = @as(u64, @intCast(non_neg));
    }
};

test "CallResult start/finish" {
    var cr = CallResult.start(.Get);
    const begin = std.time.nanoTimestamp();
    cr.finish(begin);
    try std.testing.expect(cr.duration_ns >= 0);
}
