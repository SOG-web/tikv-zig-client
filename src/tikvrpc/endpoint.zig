// TikvRPC endpoint types, ported from client-go/tikvrpc/endpoint.go
const std = @import("std");

pub const EndpointType = enum(u8) {
    TiKV,
    TiFlash,
    TiDB,

    pub fn name(self: EndpointType) []const u8 {
        return switch (self) {
            .TiKV => "tikv",
            .TiFlash => "tiflash",
            .TiDB => "tidb",
        };
    }
};

// Constants to determine engine type. Must be kept in sync with PD.
pub const engineLabelKey: []const u8 = "engine";
pub const engineLabelTiFlash: []const u8 = "tiflash";

pub const Label = struct {
    key: []const u8,
    value: []const u8,
};

/// getStoreTypeByLabels inspects store labels and returns the endpoint type.
/// If a label { key: "engine", value: "tiflash" } exists, returns TiFlash, otherwise TiKV.
pub fn getStoreTypeByLabels(labels: []const Label) EndpointType {
    for (labels) |l| {
        if (std.mem.eql(u8, l.key, engineLabelKey) and std.mem.eql(u8, l.value, engineLabelTiFlash)) {
            return .TiFlash;
        }
    }
    return .TiKV;
}

// test {
//     // Basic checks
//     try std.testing.expect(std.mem.eql(u8, EndpointType.TiKV.name(), "tikv"));
//     try std.testing.expect(std.mem.eql(u8, EndpointType.TiFlash.name(), "tiflash"));
//     try std.testing.expect(std.mem.eql(u8, EndpointType.TiDB.name(), "tidb"));

//     const labels1 = [_]Label{ .{ .key = engineLabelKey, .value = engineLabelTiFlash } };
//     try std.testing.expect(getStoreTypeByLabels(&labels1) == .TiFlash);

//     const labels2 = [_]Label{ .{ .key = "zone", .value = "a" } };
//     try std.testing.expect(getStoreTypeByLabels(&labels2) == .TiKV);
// }
