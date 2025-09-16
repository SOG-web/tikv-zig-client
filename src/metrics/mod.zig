// TiKV client Zig - metrics module root
const std = @import("std");

pub const labels = @import("labels.zig");
pub const tikv_client = @import("tikv_client.zig");
pub const shortcuts = @import("shortcuts.zig");

// Re-exports for convenience
pub const InitMetrics = tikv_client.InitMetrics;
pub const InitMetricsNS = tikv_client.InitMetricsNS;
pub const RegisterMetrics = tikv_client.RegisterMetrics;
pub const ObserveReadSLI = tikv_client.ObserveReadSLI;
pub const DeinitMetrics = tikv_client.DeinitMetrics;

// Expose the metrics instance for direct access when needed
pub const Metrics = tikv_client.Metrics;
pub var metrics = &tikv_client.metrics;

test "metrics module loads" {
    _ = labels;
    _ = tikv_client;
    _ = shortcuts;
}
