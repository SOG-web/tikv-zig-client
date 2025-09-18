// JSON to protobuf conversion helpers for PD HTTP API
const std = @import("std");
const types = @import("../types.zig");
const metapb = @import("kvproto").metapb;
const encryptionpb = @import("kvproto").encryptionpb;

const Region = types.Region;
const Store = types.Store;
const Error = types.Error;
const build_options = @import("build_options");
const pd_http_debug: bool = build_options.pd_http_debug;
const RegionEpoch = metapb.RegionEpoch;
const Peer = metapb.Peer;
const PeerRole = metapb.PeerRole;
const EncryptionMeta = encryptionpb.EncryptionMeta;
const StoreState = metapb.StoreState;
const StoreLabel = metapb.StoreLabel;
const NodeState = metapb.NodeState;

/// Stringify a JSON object map for debugging.
fn stringifyObject(allocator: std.mem.Allocator, obj: std.json.ObjectMap) ![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);
    var adp = buf.writer(allocator).adaptToNewApi(&.{});
    const w = &adp.new_interface;
    try std.json.fmt(std.json.Value{ .object = obj }, .{ .whitespace = .indent_2 }).format(w);
    return buf.toOwnedSlice(allocator);
}

/// Parse a Region from JSON object, allocating keys with the provided allocator
pub fn parseRegionFromJson(
    allocator: std.mem.Allocator,
    json_obj: std.json.ObjectMap,
) Error!Region {
    if (pd_http_debug) {
        if (stringifyObject(allocator, json_obj) catch null) |s| {
            defer allocator.free(s);
            std.debug.print("Region JSON: {s}\n", .{s});
        }
    }
    const id_val = json_obj.get("id") orelse return Error.RpcError;
    const start_key_val = json_obj.get("start_key") orelse return Error.RpcError;
    const end_key_val = json_obj.get("end_key") orelse return Error.RpcError;
    const epoch_val = json_obj.get("epoch");
    const peers_val = json_obj.get("peers");
    const encryption_meta_val = json_obj.get("encryption_meta");
    const is_in_flashback_val = json_obj.get("is_in_flashback");
    const flashback_start_ts_val = json_obj.get("flashback_start_ts");

    const id_u64: u64 = @intCast(id_val.integer);
    const start_key_str = start_key_val.string;
    const end_key_str = end_key_val.string;

    // Allocate and copy keys
    const start_key_bytes = try allocator.dupe(u8, start_key_str);
    errdefer allocator.free(start_key_bytes);
    const end_key_bytes = try allocator.dupe(u8, end_key_str);
    errdefer allocator.free(end_key_bytes);

    // Parse optional region_epoch
    var region_epoch: ?RegionEpoch = null;
    if (epoch_val) |epoch_json| {
        const epoch_obj = epoch_json.object;
        const conf_ver = if (epoch_obj.get("conf_ver")) |v| @as(u64, @intCast(v.integer)) else 0;
        const version = if (epoch_obj.get("version")) |v| @as(u64, @intCast(v.integer)) else 0;
        region_epoch = RegionEpoch{
            .conf_ver = conf_ver,
            .version = version,
        };
    }

    // Parse optional peers array
    var peers = std.ArrayListUnmanaged(Peer){};
    if (peers_val) |peers_json| {
        const peers_array = peers_json.array;
        try peers.ensureTotalCapacity(allocator, peers_array.items.len);

        for (peers_array.items) |peer_json| {
            const peer_obj = peer_json.object;
            const peer_id = if (peer_obj.get("id")) |v| @as(u64, @intCast(v.integer)) else 0;
            const store_id = if (peer_obj.get("store_id")) |v| @as(u64, @intCast(v.integer)) else 0;

            // Convert role_name string to PeerRole enum
            var role = PeerRole.Voter; // default
            if (peer_obj.get("role_name")) |role_json| {
                const role_str = role_json.string;
                if (std.mem.eql(u8, role_str, "Voter")) {
                    role = PeerRole.Voter;
                } else if (std.mem.eql(u8, role_str, "Learner")) {
                    role = PeerRole.Learner;
                } else if (std.mem.eql(u8, role_str, "IncomingVoter")) {
                    role = PeerRole.IncomingVoter;
                } else if (std.mem.eql(u8, role_str, "DemotingVoter")) {
                    role = PeerRole.DemotingVoter;
                }
            }

            const is_witness = if (peer_obj.get("is_witness")) |v| v.bool else false;

            peers.appendAssumeCapacity(Peer{
                .id = peer_id,
                .store_id = store_id,
                .role = role,
                .is_witness = is_witness,
            });
        }
    }
    errdefer peers.deinit(allocator);

    // Parse optional encryption_meta
    var encryption_meta: ?EncryptionMeta = null;
    if (encryption_meta_val) |meta_json| {
        const meta_obj = meta_json.object;
        const key_id = if (meta_obj.get("key_id")) |v| @as(u64, @intCast(v.integer)) else 0;
        const iv_str = if (meta_obj.get("iv")) |v| v.string else "";
        const iv_bytes = try allocator.dupe(u8, iv_str);
        errdefer allocator.free(iv_bytes);

        encryption_meta = EncryptionMeta{
            .key_id = key_id,
            .iv = iv_bytes,
        };
    }

    // Parse optional flashback fields
    const is_in_flashback = if (is_in_flashback_val) |v| v.bool else false;
    const flashback_start_ts = if (flashback_start_ts_val) |v| @as(u64, @intCast(v.integer)) else 0;

    // Create Region with all parsed fields
    return Region{
        .id = id_u64,
        .start_key = start_key_bytes,
        .end_key = end_key_bytes,
        .region_epoch = region_epoch,
        .peers = peers,
        .encryption_meta = encryption_meta,
        .is_in_flashback = is_in_flashback,
        .flashback_start_ts = flashback_start_ts,
    };
}

/// Parse a Store from JSON object, allocating strings with the provided allocator
pub fn parseStoreFromJson(
    allocator: std.mem.Allocator,
    json_obj: std.json.ObjectMap,
) Error!Store {
    if (pd_http_debug) {
        if (stringifyObject(allocator, json_obj) catch null) |s| {
            defer allocator.free(s);
            std.debug.print("Store JSON: {s}\n", .{s});
        }
    }
    
    // Required fields
    const id_val = json_obj.get("id") orelse return Error.RpcError;
    const addr_val = json_obj.get("address") orelse return Error.RpcError;

    const id_u64: u64 = @intCast(id_val.integer);
    const addr_str = addr_val.string;

    // Allocate and copy address
    const addr = try allocator.dupe(u8, addr_str);
    errdefer allocator.free(addr);

    // Parse optional state
    var state = StoreState.Up; // default
    if (json_obj.get("state")) |state_val| {
        const state_int = @as(i32, @intCast(state_val.integer));
        state = @enumFromInt(state_int);
    }

    // Parse optional labels array
    var labels = std.ArrayListUnmanaged(StoreLabel){};
    if (json_obj.get("labels")) |labels_json| {
        const labels_array = labels_json.array;
        try labels.ensureTotalCapacity(allocator, labels_array.items.len);
        
        for (labels_array.items) |label_json| {
            const label_obj = label_json.object;
            const key_str = if (label_obj.get("key")) |v| v.string else "";
            const value_str = if (label_obj.get("value")) |v| v.string else "";
            
            const key_bytes = try allocator.dupe(u8, key_str);
            errdefer allocator.free(key_bytes);
            
            const value_bytes = try allocator.dupe(u8, value_str);
            errdefer {
                allocator.free(value_bytes);
                allocator.free(key_bytes);
            }
            
            labels.appendAssumeCapacity(StoreLabel{
                .key = key_bytes,
                .value = value_bytes,
            });
        }
    }
    errdefer {
        for (labels.items) |*l| {
            allocator.free(l.key);
            allocator.free(l.value);
        }
        labels.deinit(allocator);
    }

    // Parse optional string fields
    const version_str = if (json_obj.get("version")) |v| v.string else "";
    const version = try allocator.dupe(u8, version_str);
    errdefer allocator.free(version);

    const peer_address_str = if (json_obj.get("peer_address")) |v| v.string else "";
    const peer_address = try allocator.dupe(u8, peer_address_str);
    errdefer allocator.free(peer_address);

    const status_address_str = if (json_obj.get("status_address")) |v| v.string else "";
    const status_address = try allocator.dupe(u8, status_address_str);
    errdefer allocator.free(status_address);

    const git_hash_str = if (json_obj.get("git_hash")) |v| v.string else "";
    const git_hash = try allocator.dupe(u8, git_hash_str);
    errdefer allocator.free(git_hash);

    const deploy_path_str = if (json_obj.get("deploy_path")) |v| v.string else "";
    const deploy_path = try allocator.dupe(u8, deploy_path_str);
    errdefer allocator.free(deploy_path);

    // Parse optional integer/boolean fields
    const start_timestamp = if (json_obj.get("start_timestamp")) |v| @as(i64, @intCast(v.integer)) else 0;
    const last_heartbeat = if (json_obj.get("last_heartbeat")) |v| @as(i64, @intCast(v.integer)) else 0;
    const physically_destroyed = if (json_obj.get("physically_destroyed")) |v| v.bool else false;
    
    // Parse optional node_state
    var node_state = NodeState.Preparing; // default
    if (json_obj.get("node_state")) |node_state_val| {
        const node_state_int = @as(i32, @intCast(node_state_val.integer));
        node_state = @enumFromInt(node_state_int);
    }

    // Create Store with all parsed fields
    return Store{
        .id = id_u64,
        .address = addr,
        .state = state,
        .labels = labels,
        .version = version,
        .peer_address = peer_address,
        .status_address = status_address,
        .git_hash = git_hash,
        .start_timestamp = start_timestamp,
        .deploy_path = deploy_path,
        .last_heartbeat = last_heartbeat,
        .physically_destroyed = physically_destroyed,
        .node_state = node_state,
    };
}

/// Parse a Store from a wrapped JSON object (e.g., {"store": {...}, "status": {...}})
pub fn parseStoreFromWrappedJson(
    allocator: std.mem.Allocator,
    wrapper_obj: std.json.ObjectMap,
) Error!Store {
    const store_obj_val = wrapper_obj.get("store") orelse return Error.RpcError;
    const store_obj = store_obj_val.object;
    return parseStoreFromJson(allocator, store_obj);
}

test {
    std.testing.refAllDecls(@This());
}
