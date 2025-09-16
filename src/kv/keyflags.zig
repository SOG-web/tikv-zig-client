// TiKV client Zig - kv/keyflags
const std = @import("std");

/// KeyFlags are metadata associated with a key.
pub const KeyFlags = u16;

pub const FlagBytes: usize = 2;

const flagPresumeKNE: KeyFlags = 1 << 0;
const flagKeyLocked: KeyFlags = 1 << 1;
const flagNeedLocked: KeyFlags = 1 << 2;
const flagKeyLockedValExist: KeyFlags = 1 << 3;
const flagNeedCheckExists: KeyFlags = 1 << 4;
const flagPrewriteOnly: KeyFlags = 1 << 5;
const flagIgnoredIn2PC: KeyFlags = 1 << 6;
const flagReadable: KeyFlags = 1 << 7;
const flagNewlyInserted: KeyFlags = 1 << 8;
// Assertion flags (two bits)
const flagAssertExist: KeyFlags = 1 << 9;
const flagAssertNotExist: KeyFlags = 1 << 10;

const persistentFlags: KeyFlags = flagKeyLocked | flagKeyLockedValExist;

pub inline fn hasAssertExist(f: KeyFlags) bool {
    return (f & flagAssertExist) != 0 and (f & flagAssertNotExist) == 0;
}

pub inline fn hasAssertNotExist(f: KeyFlags) bool {
    return (f & flagAssertNotExist) != 0 and (f & flagAssertExist) == 0;
}

pub inline fn hasAssertUnknown(f: KeyFlags) bool {
    return (f & flagAssertExist) != 0 and (f & flagAssertNotExist) != 0;
}

pub inline fn hasAssertionFlags(f: KeyFlags) bool {
    return (f & flagAssertExist) != 0 or (f & flagAssertNotExist) != 0;
}

pub inline fn hasPresumeKeyNotExists(f: KeyFlags) bool {
    return (f & flagPresumeKNE) != 0;
}

pub inline fn hasLocked(f: KeyFlags) bool { return (f & flagKeyLocked) != 0; }

pub inline fn hasNeedLocked(f: KeyFlags) bool { return (f & flagNeedLocked) != 0; }

pub inline fn hasLockedValueExists(f: KeyFlags) bool { return (f & flagKeyLockedValExist) != 0; }

pub inline fn hasNeedCheckExists(f: KeyFlags) bool { return (f & flagNeedCheckExists) != 0; }

pub inline fn hasPrewriteOnly(f: KeyFlags) bool { return (f & flagPrewriteOnly) != 0; }

pub inline fn hasIgnoredIn2PC(f: KeyFlags) bool { return (f & flagIgnoredIn2PC) != 0; }

pub inline fn hasReadable(f: KeyFlags) bool { return (f & flagReadable) != 0; }

pub inline fn andPersistent(f: KeyFlags) KeyFlags { return f & persistentFlags; }

pub inline fn hasNewlyInserted(f: KeyFlags) bool { return (f & flagNewlyInserted) != 0; }

pub const FlagsOp = u32;

pub const SetPresumeKeyNotExists: FlagsOp = 1 << 0;
pub const DelPresumeKeyNotExists: FlagsOp = 1 << 1;
pub const SetKeyLocked: FlagsOp = 1 << 2;
pub const DelKeyLocked: FlagsOp = 1 << 3;
pub const SetNeedLocked: FlagsOp = 1 << 4;
pub const DelNeedLocked: FlagsOp = 1 << 5;
pub const SetKeyLockedValueExists: FlagsOp = 1 << 6;
pub const SetKeyLockedValueNotExists: FlagsOp = 1 << 7;
pub const DelNeedCheckExists: FlagsOp = 1 << 8;
pub const SetPrewriteOnly: FlagsOp = 1 << 9;
pub const SetIgnoredIn2PC: FlagsOp = 1 << 10;
pub const SetReadable: FlagsOp = 1 << 11;
pub const SetNewlyInserted: FlagsOp = 1 << 12;
pub const SetAssertExist: FlagsOp = 1 << 13;
pub const SetAssertNotExist: FlagsOp = 1 << 14;
pub const SetAssertUnknown: FlagsOp = 1 << 15;
pub const SetAssertNone: FlagsOp = 1 << 16;

/// Apply a sequence of flag operations to the original flags.
pub fn applyFlagsOps(origin_in: KeyFlags, ops: []const FlagsOp) KeyFlags {
    var origin = origin_in;
    for (ops) |op| {
        if (op == SetPresumeKeyNotExists) {
            origin |= flagPresumeKNE | flagNeedCheckExists;
        } else if (op == DelPresumeKeyNotExists) {
            origin &= ~(@as(KeyFlags, flagPresumeKNE | flagNeedCheckExists));
        } else if (op == SetKeyLocked) {
            origin |= flagKeyLocked;
        } else if (op == DelKeyLocked) {
            origin &= ~flagKeyLocked;
        } else if (op == SetNeedLocked) {
            origin |= flagNeedLocked;
        } else if (op == DelNeedLocked) {
            origin &= ~flagNeedLocked;
        } else if (op == SetKeyLockedValueExists) {
            origin |= flagKeyLockedValExist;
        } else if (op == DelNeedCheckExists) {
            origin &= ~flagNeedCheckExists;
        } else if (op == SetKeyLockedValueNotExists) {
            origin &= ~flagKeyLockedValExist;
        } else if (op == SetPrewriteOnly) {
            origin |= flagPrewriteOnly;
        } else if (op == SetIgnoredIn2PC) {
            origin |= flagIgnoredIn2PC;
        } else if (op == SetReadable) {
            origin |= flagReadable;
        } else if (op == SetNewlyInserted) {
            origin |= flagNewlyInserted;
        } else if (op == SetAssertExist) {
            origin &= ~flagAssertNotExist;
            origin |= flagAssertExist;
        } else if (op == SetAssertNotExist) {
            origin &= ~flagAssertExist;
            origin |= flagAssertNotExist;
        } else if (op == SetAssertUnknown) {
            origin |= flagAssertNotExist;
            origin |= flagAssertExist;
        } else if (op == SetAssertNone) {
            origin &= ~flagAssertExist;
            origin &= ~flagAssertNotExist;
        }
    }
    return origin;
}

// -------------------- Tests --------------------

test "applyFlagsOps basic" {
    var f: KeyFlags = 0;
    f = applyFlagsOps(f, &.{ SetPresumeKeyNotExists });
    try std.testing.expect(hasPresumeKeyNotExists(f));
    try std.testing.expect(hasNeedCheckExists(f));
    f = applyFlagsOps(f, &.{ DelPresumeKeyNotExists });
    try std.testing.expect(!hasPresumeKeyNotExists(f));
    try std.testing.expect(!hasNeedCheckExists(f));
}
