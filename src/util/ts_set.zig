const std = @import("std");

// TSSet is a thread-safe set of u64 timestamps.
pub const TSSet = struct {
    lock: std.Thread.RwLock = .{},
    map: ?std.AutoHashMap(u64, void) = null, // lazy init for perf

    pub fn init() TSSet {
        return .{};
    }

    pub fn deinit(self: *TSSet, allocator: std.mem.Allocator) void {
        if (self.map) |*m| {
            m.deinit();
            self.map = null;
        }
        _ = allocator; // lock has no deinit
    }

    // Put inserts timestamps into the set.
    pub fn put(self: *TSSet, allocator: std.mem.Allocator, tss: []const u64) !void {
        self.lock.lock();
        defer self.lock.unlock();
        if (self.map == null) {
            var m = std.AutoHashMap(u64, void).init(allocator);
            try m.ensureTotalCapacity(@max(tss.len, 5));
            self.map = m;
        }
        var mref = &self.map.?.*;
        for (tss) |ts| {
            try mref.put(ts, {});
        }
    }

    // getAll returns a newly allocated slice of all timestamps.
    pub fn getAll(self: *TSSet, allocator: std.mem.Allocator) ![]u64 {
        self.lock.lockShared();
        defer self.lock.unlockShared();
        if (self.map == null or self.map.?.count() == 0) return allocator.alloc(u64, 0);
        const mref = &self.map.?.*;
        var out = try allocator.alloc(u64, mref.count());
        var i: usize = 0;
        var it = mref.keyIterator();
        while (it.next()) |k| : (i += 1) {
            out[i] = k.*;
        }
        return out;
    }
};

// ---- tests ----

test "ts_set basic" {
    const gpa = std.testing.allocator;
    var s = TSSet.init();
    defer s.deinit(gpa);

    try s.put(gpa, &[_]u64{1, 2, 3, 2});
    const all = try s.getAll(gpa);
    defer gpa.free(all);
    // contains 1,2,3 in some order
    var seen1 = false; var seen2 = false; var seen3 = false;
    for (all) |v| switch (v) { 1 => seen1 = true, 2 => seen2 = true, 3 => seen3 = true, else => {} };
    try std.testing.expect(seen1 and seen2 and seen3);
}
