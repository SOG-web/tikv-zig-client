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

// Re-export all config modules
pub const config = @import("config.zig");
pub const client = @import("client.zig");
pub const security = @import("security.zig");

// Re-export main types for convenience
pub const Config = config.Config;
pub const TiKVClient = client.TiKVClient;
pub const Security = security.Security;
pub const TLSConfig = security.TLSConfig;
pub const PDClient = config.PDClient;
pub const TxnLocalLatches = config.TxnLocalLatches;
pub const PessimisticTxn = config.PessimisticTxn;
pub const AsyncCommit = client.AsyncCommit;
pub const CoprocessorCache = client.CoprocessorCache;

// Re-export main functions
pub const initGlobalConfig = config.initGlobalConfig;
pub const getGlobalConfig = config.getGlobalConfig;
pub const storeGlobalConfig = config.storeGlobalConfig;
pub const updateGlobal = config.updateGlobal;
pub const getTxnScopeFromConfig = config.getTxnScopeFromConfig;
pub const parsePath = config.parsePath;

// Re-export constants
pub const DEF_STORES_REFRESH_INTERVAL = config.DEF_STORES_REFRESH_INTERVAL;
pub const DEF_STORE_LIVENESS_TIMEOUT = client.DEF_STORE_LIVENESS_TIMEOUT;

test {
    // Import all tests from submodules
    _ = config;
    _ = client;
    _ = security;
}
