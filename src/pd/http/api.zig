// PD HTTP API endpoints constants (mirrors pd-client/http/api.go)
const std = @import("std");

// Metadata
pub const HotRead: []const u8 = "/pd/api/v1/hotspot/regions/read";
pub const HotWrite: []const u8 = "/pd/api/v1/hotspot/regions/write";
pub const HotHistory: []const u8 = "/pd/api/v1/hotspot/regions/history";

pub const RegionByIDPrefix: []const u8 = "/pd/api/v1/region/id"; // append "/<id>"
pub const RegionByKey: []const u8 = "/pd/api/v1/region/key";   // append "/<escaped-key>"
pub const RegionByIDPrefixSlash: []const u8 = "/pd/api/v1/region/id/"; // convenience constant with trailing slash
pub const RegionByKeyPrefix: []const u8 = "/pd/api/v1/region/key/";   // convenience constant with trailing slash

pub const Regions: []const u8 = "/pd/api/v1/regions";
pub const RegionsByKey: []const u8 = "/pd/api/v1/regions/key"; // uses query params: ?key=...&end_key=...&limit=...

pub const RegionsByStoreIDPrefix: []const u8 = "/pd/api/v1/regions/store"; // append "/<store_id>"
pub const RegionsReplicated: []const u8 = "/pd/api/v1/regions/replicated";
pub const RegionsSiblings: []const u8 = "/pd/api/v1/regions/sibling";

pub const EmptyRegions: []const u8 = "/pd/api/v1/regions/check/empty-region";

pub const AccelerateSchedule: []const u8 = "/pd/api/v1/regions/accelerate-schedule";
pub const AccelerateScheduleInBatch: []const u8 = "/pd/api/v1/regions/accelerate-schedule/batch";

pub const Store: []const u8 = "/pd/api/v1/store";   // append "/<id>"
pub const Stores: []const u8 = "/pd/api/v1/stores";
pub const StorePrefix: []const u8 = "/pd/api/v1/store/";   // convenience constant with trailing slash

pub const StatsRegion: []const u8 = "/pd/api/v1/stats/region";

pub const MembersPrefix: []const u8 = "/pd/api/v1/members";
pub const LeaderPrefix: []const u8 = "/pd/api/v1/leader";

pub const TransferLeader: []const u8 = "/pd/api/v1/leader/transfer";

pub const Health: []const u8 = "/pd/api/v1/health";

// Config
pub const Config: []const u8 = "/pd/api/v1/config";
pub const ClusterVersion: []const u8 = "/pd/api/v1/config/cluster-version";
pub const ScheduleConfig: []const u8 = "/pd/api/v1/config/schedule";
pub const ReplicateConfig: []const u8 = "/pd/api/v1/config/replicate";

// Rule
pub const PlacementRule: []const u8 = "/pd/api/v1/config/rule";
pub const PlacementRules: []const u8 = "/pd/api/v1/config/rules";
pub const PlacementRulesInBatch: []const u8 = "/pd/api/v1/config/rules/batch";
pub const PlacementRulesByGroup: []const u8 = "/pd/api/v1/config/rules/group";
pub const PlacementRuleBundle: []const u8 = "/pd/api/v1/config/placement-rule";
pub const PlacementRuleGroup: []const u8 = "/pd/api/v1/config/rule_group";
pub const PlacementRuleGroups: []const u8 = "/pd/api/v1/config/rule_groups";

pub const RegionLabelRule: []const u8 = "/pd/api/v1/config/region-label/rule";
pub const RegionLabelRules: []const u8 = "/pd/api/v1/config/region-label/rules";
pub const RegionLabelRulesByIDs: []const u8 = "/pd/api/v1/config/region-label/rules/ids";

// Scheduler
pub const Schedulers: []const u8 = "/pd/api/v1/schedulers";
pub const SchedulerConfig: []const u8 = "/pd/api/v1/scheduler-config";
pub const ScatterRangeScheduler: []const u8 = "/pd/api/v1/schedulers/scatter-range-scheduler-"; // append suffix

// Admin
pub const ResetTS: []const u8 = "/pd/api/v1/admin/reset-ts";
pub const BaseAllocID: []const u8 = "/pd/api/v1/admin/base-alloc-id";
pub const SnapshotRecoveringMark: []const u8 = "/pd/api/v1/admin/cluster/markers/snapshot-recovering";

// Debug
pub const PProfProfile: []const u8 = "/pd/api/v1/debug/pprof/profile";
pub const PProfHeap: []const u8 = "/pd/api/v1/debug/pprof/heap";
pub const PProfMutex: []const u8 = "/pd/api/v1/debug/pprof/mutex";
pub const PProfAllocs: []const u8 = "/pd/api/v1/debug/pprof/allocs";
pub const PProfBlock: []const u8 = "/pd/api/v1/debug/pprof/block";
pub const PProfGoroutine: []const u8 = "/pd/api/v1/debug/pprof/goroutine";

// Others
pub const MinResolvedTSPrefix: []const u8 = "/pd/api/v1/min-resolved-ts";
pub const Cluster: []const u8 = "/pd/api/v1/cluster";
pub const ClusterStatus: []const u8 = "/pd/api/v1/cluster/status";
pub const Status: []const u8 = "/pd/api/v1/status";
pub const Version: []const u8 = "/pd/api/v1/version";

pub const Operators: []const u8 = "/pd/api/v1/operators";
pub const Safepoint: []const u8 = "/pd/api/v1/gc/safepoint";

// Microservice
pub const MicroservicePrefix: []const u8 = "/pd/api/v2/ms";

// Keyspace
pub const KeyspaceConfig: []const u8 = "/pd/api/v2/keyspaces/%s/config"; // format with name
pub const GetKeyspaceMetaByName: []const u8 = "/pd/api/v2/keyspaces/%s"; // format with name
pub const GetKeyspaceMetaByID: []const u8 = "/pd/api/v2/keyspaces/id/%d"; // format with id

// Safe builders for keyspace endpoints
pub fn buildKeyspaceConfig(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "/pd/api/v2/keyspaces/{s}/config", .{name});
}

pub fn buildKeyspaceMetaByName(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "/pd/api/v2/keyspaces/{s}", .{name});
}

pub fn buildKeyspaceMetaByID(allocator: std.mem.Allocator, id: u64) ![]u8 {
    return std.fmt.allocPrint(allocator, "/pd/api/v2/keyspaces/id/{d}", .{id});
}

// Basic check to ensure module compiles
test {
    std.testing.refAllDecls(@This());
}
