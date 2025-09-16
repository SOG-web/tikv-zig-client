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

// Re-export all error types and functions
pub const error_types = @import("error.zig");

// Re-export main types for convenience
pub const TiKVError = error_types.TiKVError;
pub const ErrDeadlock = error_types.ErrDeadlock;
pub const PDError = error_types.PDError;
pub const ErrKeyExist = error_types.ErrKeyExist;
pub const ErrWriteConflict = error_types.ErrWriteConflict;
pub const ErrWriteConflictInLatch = error_types.ErrWriteConflictInLatch;
pub const ErrRetryable = error_types.ErrRetryable;
pub const ErrTxnTooLarge = error_types.ErrTxnTooLarge;
pub const ErrEntryTooLarge = error_types.ErrEntryTooLarge;
pub const ErrPDServerTimeout = error_types.ErrPDServerTimeout;
pub const ErrGCTooEarly = error_types.ErrGCTooEarly;
pub const ErrTokenLimit = error_types.ErrTokenLimit;
pub const ErrAssertionFailed = error_types.ErrAssertionFailed;
pub const ErrCommitTsTooLarge = error_types.ErrCommitTsTooLarge;

// Re-export main functions
pub const isErrWriteConflict = error_types.isErrWriteConflict;
pub const newErrWriteConflictWithArgs = error_types.newErrWriteConflictWithArgs;
pub const extractKeyErr = error_types.extractKeyErr;
pub const isErrNotFound = error_types.isErrNotFound;
pub const isErrorUndetermined = error_types.isErrorUndetermined;
pub const logError = error_types.logError;

test {
    // Import all tests from submodules
    _ = error_types;
}
