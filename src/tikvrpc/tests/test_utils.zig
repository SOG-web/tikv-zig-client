// Test utilities for TiKV RPC tests
const std = @import("std");
const c = @import("../../c.zig").c;

pub const TestArena = struct {
    arena: [*c]c.upb_Arena,

    pub fn init() TestArena {
        return TestArena{
            .arena = c.upb_Arena_New(),
        };
    }

    pub fn deinit(self: *TestArena) void {
        c.upb_Arena_Free(self.arena);
    }
};

pub fn expectStringViewEq(actual: c.upb_StringView, expected: []const u8) !void {
    if (actual.size != expected.len) {
        std.debug.print("String length mismatch: expected {}, got {}\n", .{ expected.len, actual.size });
        return error.TestExpectedEqual;
    }
    
    const actual_slice = actual.data[0..actual.size];
    if (!std.mem.eql(u8, actual_slice, expected)) {
        std.debug.print("String content mismatch: expected '{s}', got '{s}'\n", .{ expected, actual_slice });
        return error.TestExpectedEqual;
    }
}

pub fn createTestRegion(arena: *c.upb_Arena, region_id: u64, start_key: []const u8, end_key: []const u8) *c.metapb_Region {
    const region = c.metapb_Region_new(arena) orelse unreachable;
    c.metapb_Region_set_id(region, region_id);
    c.metapb_Region_set_start_key(region, .{ .data = start_key.ptr, .size = start_key.len });
    c.metapb_Region_set_end_key(region, .{ .data = end_key.ptr, .size = end_key.len });
    return region;
}

pub fn createTestPeer(arena: *c.upb_Arena, peer_id: u64, store_id: u64) *c.metapb_Peer {
    const peer = c.metapb_Peer_new(arena) orelse unreachable;
    c.metapb_Peer_set_id(peer, peer_id);
    c.metapb_Peer_set_store_id(peer, store_id);
    return peer;
}

pub fn createTestContext(arena: [*c]c.upb_Arena, region_id: u64, peer_id: u64, store_id: u64) *c.kvrpcpb_Context {
    const ctx = c.kvrpcpb_Context_new(arena) orelse unreachable;
    c.kvrpcpb_Context_set_region_id(ctx, region_id);
    
    const peer = c.kvrpcpb_Context_mutable_peer(ctx, arena) orelse unreachable;
    c.metapb_Peer_set_id(peer, peer_id);
    c.metapb_Peer_set_store_id(peer, store_id);
    
    const epoch = c.kvrpcpb_Context_mutable_region_epoch(ctx, arena) orelse unreachable;
    c.metapb_RegionEpoch_set_conf_ver(epoch, 1);
    c.metapb_RegionEpoch_set_version(epoch, 1);
    
    return ctx;
}

// Test data generators
pub const TestData = struct {
    pub const keys = [_][]const u8{
        "test_key_1",
        "test_key_2", 
        "test_key_3",
        "batch_key_1",
        "batch_key_2",
        "primary_key",
        "secondary_key_1",
        "secondary_key_2",
    };
    
    pub const values = [_][]const u8{
        "test_value_1",
        "test_value_2",
        "test_value_3", 
        "batch_value_1",
        "batch_value_2",
    };
    
    pub const timestamps = struct {
        pub const start_ts: u64 = 1000000;
        pub const commit_ts: u64 = 1000001;
        pub const for_update_ts: u64 = 1000002;
        pub const current_ts: u64 = 1000003;
        pub const safe_point: u64 = 999999;
    };
    
    pub const ttl = struct {
        pub const lock_ttl: u64 = 60000; // 60 seconds
        pub const advise_ttl: u64 = 120000; // 120 seconds
    };
};
