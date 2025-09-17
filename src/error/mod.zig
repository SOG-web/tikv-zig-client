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

// Split module re-exports
const common = @import("common.zig");
const deadlock = @import("deadlock.zig");
const pd_error = @import("pd_error.zig");
const write_conflict = @import("write_conflict.zig");
const kv_errors = @import("kv_errors.zig");
const assertion_failed = @import("assertion_failed.zig");
const key_error = @import("key_error.zig");

// Re-export main types for convenience
pub const TiKVError = common.TiKVError;
pub const ErrDeadlock = deadlock.ErrDeadlock;
pub const PDError = pd_error.PDError;
pub const ErrKeyExist = kv_errors.ErrKeyExist;
pub const ErrWriteConflict = write_conflict.ErrWriteConflict;
pub const ErrWriteConflictInLatch = write_conflict.ErrWriteConflictInLatch;
pub const ErrRetryable = kv_errors.ErrRetryable;
pub const ErrTxnTooLarge = kv_errors.ErrTxnTooLarge;
pub const ErrEntryTooLarge = kv_errors.ErrEntryTooLarge;
pub const ErrPDServerTimeout = kv_errors.ErrPDServerTimeout;
pub const ErrGCTooEarly = kv_errors.ErrGCTooEarly;
pub const ErrTokenLimit = kv_errors.ErrTokenLimit;
pub const ErrAssertionFailed = assertion_failed.ErrAssertionFailed;
pub const ErrCommitTsTooLarge = kv_errors.ErrCommitTsTooLarge;

// Re-export main functions
pub const isErrWriteConflict = write_conflict.isErrWriteConflict;
pub const newErrWriteConflictWithArgs = write_conflict.newErrWriteConflictWithArgs;
pub const extractKeyErr = key_error.extractKeyErr;
pub const isErrNotFound = common.isErrNotFound;
pub const isErrorUndetermined = common.isErrorUndetermined;
pub const logError = common.logError;

// KeyError result helpers
pub const KeyErrorResult = key_error.KeyErrorResult;
pub const formatKeyErrorResult = key_error.formatKeyErrorResult;
pub const deinitKeyErrorResult = key_error.deinitKeyErrorResult;
pub const isErrKeyExist = key_error.isErrKeyExist;

test {
    // Pull in tests from submodules
    _ = common;
    _ = deadlock;
    _ = pd_error;
    _ = write_conflict;
    _ = kv_errors;
    _ = assertion_failed;
    _ = key_error;
}
