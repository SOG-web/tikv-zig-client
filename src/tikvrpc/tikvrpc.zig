// TikvRPC core types and utilities (skeleton)
const std = @import("std");

/// CmdType mirrors tikvrpc.CmdType in Go. Values are stable for wire mapping.
pub const CmdType = enum(u16) {
    // 1xx txn
    CmdGet = 1,
    CmdScan = 2,
    CmdPrewrite = 3,
    CmdCommit = 4,
    CmdCleanup = 5,
    CmdBatchGet = 6,
    CmdBatchRollback = 7,
    CmdScanLock = 8,
    CmdResolveLock = 9,
    CmdGC = 10,
    CmdDeleteRange = 11,
    CmdPessimisticLock = 12,
    CmdPessimisticRollback = 13,
    CmdTxnHeartBeat = 14,
    CmdCheckTxnStatus = 15,
    CmdCheckSecondaryLocks = 16,

    // 256+ raw
    CmdRawGet = 256,
    CmdRawBatchGet = 257,
    CmdRawPut = 258,
    CmdRawBatchPut = 259,
    CmdRawDelete = 260,
    CmdRawBatchDelete = 261,
    CmdRawDeleteRange = 262,
    CmdRawScan = 263,
    CmdGetKeyTTL = 264,
    CmdRawCompareAndSwap = 265,

    CmdUnsafeDestroyRange = 266,

    CmdRegisterLockObserver = 267,
    CmdCheckLockObserver = 268,
    CmdRemoveLockObserver = 269,
    CmdPhysicalScanLock = 270,

    CmdStoreSafeTS = 271,
    CmdLockWaitInfo = 272,

    // 512+ cop/mpp
    CmdCop = 512,
    CmdCopStream = 513,
    CmdBatchCop = 514,
    CmdMPPTask = 515,
    CmdMPPConn = 516,
    CmdMPPCancel = 517,
    CmdMPPAlive = 518,

    // 1024+ mvcc/split
    CmdMvccGetByKey = 1024,
    CmdMvccGetByStartTs = 1025,
    CmdSplitRegion = 1026,

    // 2048+ debug
    CmdDebugGetRegionProperties = 2048,

    // 3072+ misc
    CmdEmpty = 3072,
};

pub fn cmdTypeName(t: CmdType) []const u8 {
    return switch (t) {
        .CmdGet => "Get",
        .CmdScan => "Scan",
        .CmdPrewrite => "Prewrite",
        .CmdPessimisticLock => "PessimisticLock",
        .CmdPessimisticRollback => "PessimisticRollback",
        .CmdCommit => "Commit",
        .CmdCleanup => "Cleanup",
        .CmdBatchGet => "BatchGet",
        .CmdBatchRollback => "BatchRollback",
        .CmdScanLock => "ScanLock",
        .CmdResolveLock => "ResolveLock",
        .CmdGC => "GC",
        .CmdDeleteRange => "DeleteRange",
        .CmdRawGet => "RawGet",
        .CmdRawBatchGet => "RawBatchGet",
        .CmdRawPut => "RawPut",
        .CmdRawBatchPut => "RawBatchPut",
        .CmdRawDelete => "RawDelete",
        .CmdRawBatchDelete => "RawBatchDelete",
        .CmdRawDeleteRange => "RawDeleteRange",
        .CmdRawScan => "RawScan",
        .CmdGetKeyTTL => "GetKeyTTL",
        .CmdRawCompareAndSwap => "RawCompareAndSwap",
        .CmdUnsafeDestroyRange => "UnsafeDestroyRange",
        .CmdRegisterLockObserver => "RegisterLockObserver",
        .CmdCheckLockObserver => "CheckLockObserver",
        .CmdRemoveLockObserver => "RemoveLockObserver",
        .CmdPhysicalScanLock => "PhysicalScanLock",
        .CmdCop => "Cop",
        .CmdCopStream => "CopStream",
        .CmdBatchCop => "BatchCop",
        .CmdMPPTask => "DispatchMPPTask",
        .CmdMPPConn => "EstablishMPPConnection",
        .CmdMPPCancel => "CancelMPPTask",
        .CmdMPPAlive => "MPPAlive",
        .CmdMvccGetByKey => "MvccGetByKey",
        .CmdMvccGetByStartTs => "MvccGetByStartTS",
        .CmdSplitRegion => "SplitRegion",
        .CmdCheckTxnStatus => "CheckTxnStatus",
        .CmdCheckSecondaryLocks => "CheckSecondaryLocks",
        .CmdDebugGetRegionProperties => "DebugGetRegionProperties",
        .CmdTxnHeartBeat => "TxnHeartBeat",
        .CmdStoreSafeTS => "StoreSafeTS",
        .CmdLockWaitInfo => "LockWaitInfo",
        .CmdEmpty => "Empty",
    };
}

test {
    try std.testing.expectEqualStrings("Get", cmdTypeName(.CmdGet));
    try std.testing.expectEqualStrings("RawGet", cmdTypeName(.CmdRawGet));
    try std.testing.expectEqualStrings("Cop", cmdTypeName(.CmdCop));
}
