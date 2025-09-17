const std = @import("std");
const kvproto = @import("kvproto");
const metapb = kvproto.metapb;

// Shared types for tikvrpc module
pub const EndpointType = enum(u8) {
    TiKV,
    TiFlash,
    TiDB,
};

pub fn name(self: EndpointType) []const u8 {
    return switch (self) {
        .TiKV => "tikv",
        .TiFlash => "tiflash",
        .TiDB => "tidb",
    };
}

pub const engineLabelKey = "engine";
pub const engineLabelTiFlash = "tiflash";

pub fn getStoreTypeByMeta(store: *const metapb.Store) EndpointType {
    const labels = store.labels.items;
    for (labels) |lbl| {
        if (std.mem.eql(u8, lbl.key, engineLabelKey) and std.mem.eql(u8, lbl.value, engineLabelTiFlash)) {
            return .TiFlash;
        }
    }
    return .TiKV;
}
