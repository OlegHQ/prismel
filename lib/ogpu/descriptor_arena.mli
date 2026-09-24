type t
type allocation

val create : device:Handle.device -> capacity:int -> (t,Error.t) result
val allocate : Handle.device -> t -> count:int -> (allocation,Error.t) result
val slots : allocation -> int array
val generations : allocation -> int64 array
val validate : Handle.device -> allocation -> (unit,Error.t) result
val mark_submitted : allocation -> Submission.receipt -> (unit,Error.t) result
val release : allocation -> (unit,Error.t) result
val reset : t -> completed_epoch:int64 -> (unit,Error.t) result
val live_count : t -> int
val pending_count : t -> int
val metadata_count : t -> int
val completed_epoch : t -> int64
val destroy : t -> (unit,Error.t) result
