const std = @import("std");

// Minimal context to carry a session ID, analogous to Go's context WithValue usage in misc.go.
// Extendable to store more metadata later.
pub const Context = struct {
    session_id: ?u64 = null,

    pub fn setSessionID(self: *Context, session_id: u64) void {
        self.session_id = session_id;
    }

    pub fn getSessionID(self: *const Context) ?u64 {
        return self.session_id;
    }
};

// ---- tests ----

test "session set/get" {
    var ctx = Context{};
    try std.testing.expect(ctx.getSessionID() == null);
    ctx.setSessionID(42);
    try std.testing.expectEqual(@as(?u64, 42), ctx.getSessionID());
}
