// Copyright 2021 TiKV Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! Oracle module provides strictly ascending timestamps for TiKV transactions.
//!
//! This module contains:
//! - Oracle interface for timestamp generation
//! - Timestamp composition and extraction utilities
//! - Future/async timestamp request handling

const std = @import("std");
const pd = @import("../pd/client.zig");
const oracles_mod = @import("oracles/mod.zig");

pub const oracle = @import("oracle.zig");
pub const oracles = @import("oracles/mod.zig");

// Re-export main types
pub const Oracle = oracle.Oracle;
pub const Future = oracle.Future;
pub const Option = oracle.Option;

// Re-export timestamp utilities
pub const composeTS = oracle.composeTS;
pub const extractPhysical = oracle.extractPhysical;
pub const extractLogical = oracle.extractLogical;
pub const getPhysical = oracle.getPhysical;
pub const msToTS = oracle.msToTS;
pub const lowerLimitStartTSFromNow = oracle.lowerLimitStartTSFromNow;

// Re-export oracle implementations
pub const PdOracle = oracles.pd.PdOracle;

// Constants
pub const GLOBAL_TXN_SCOPE = oracle.GLOBAL_TXN_SCOPE;

test {
    std.testing.refAllDecls(@This());
}

/// Bundle that owns both a PDClient and a PdOracle for simple app wiring.
pub const PDOracleBundle = struct {
    client: pd.PDClient,
    oracle_ptr: *PdOracle,

    pub fn oracle(self: PDOracleBundle) Oracle {
        return self.oracle_ptr.oracle();
    }

    pub fn close(self: PDOracleBundle) void {
        self.oracle_ptr.deinit();
        self.client.close();
    }
};

/// Factory: build a PD client and a PdOracle with one call.
pub fn build_pd_oracle(
    allocator: std.mem.Allocator,
    endpoints: []const []const u8,
    prefer_grpc: bool,
    use_https: bool,
    refresh_ms: u64,
) !PDOracleBundle {
    var client = try pd.PDClientFactory.grpc_with_transport_options(allocator, endpoints, prefer_grpc, use_https, .{});
    errdefer client.close();

    var pd_oracle = try oracles_mod.PdOracle.init(allocator, client, refresh_ms);
    errdefer pd_oracle.deinit();

    return PDOracleBundle{ .client = client, .oracle_ptr = pd_oracle };
}

test {
    std.testing.refAllDecls(@This());
    _ = @import("tests/pd_oracle_smoke_test.zig");
}
