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

//! Oracle implementations module

pub const pd = @import("pd.zig");
pub const local = @import("local.zig");
pub const mock = @import("mock.zig");

// Re-export main types
pub const PdOracle = pd.PdOracle;
pub const LocalOracle = local.LocalOracle;
pub const MockOracle = mock.MockOracle;

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
