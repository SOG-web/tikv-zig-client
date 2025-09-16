// TiKV client Zig - metrics/labels
pub const LblKind = "kind"; // 'type' in Go, reserved in Zig -> use 'kind'
pub const LblResult = "result";
pub const LblStore = "store";
pub const LblCommit = "commit";
pub const LblAbort = "abort";
pub const LblRollback = "rollback";
pub const LblBatchGet = "batch_get";
pub const LblGet = "get";
pub const LblLockKeys = "lock_keys";
pub const LabelBatchRecvLoop = "batch-recv-loop";
pub const LabelBatchSendLoop = "batch-send-loop";
pub const LblAddress = "address";
pub const LblFromStore = "from_store";
pub const LblToStore = "to_store";
pub const LblStaleRead = "stale_read";
