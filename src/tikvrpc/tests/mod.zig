// Test module for TiKV RPC operations
// This module exports all test files for easy running

// Test utilities
pub const test_utils = @import("test_utils.zig");

// Core functionality tests
pub const transactional_test = @import("transactional_test.zig");
pub const rawkv_test = @import("rawkv_test.zig");
pub const batch_test = @import("batch_test.zig");

// Error handling and edge cases
pub const error_test = @import("error_test.zig");

// Integration and workflow tests
pub const integration_test = @import("integration_test.zig");

// Test runner for all tests
test {
    // Import all test files to ensure they are run
    _ = transactional_test;
    _ = rawkv_test;
    _ = batch_test;
    _ = error_test;
    _ = integration_test;
}
