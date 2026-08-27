type direction = Upload | Readback
type policy = Copy | Borrow
type t
type reservation
type snapshot = { index:int64; offset:int64; length:int64; direction:direction; policy:policy }
val create : device:Handle.device -> capacity:int64 -> alignment:int64 -> max_slots:int -> (t,Error.t) result
val reserve : t -> direction:direction -> policy:policy -> ?bytes:bytes -> length:int64 -> unit -> (reservation,Error.t) result
val commit : reservation -> epoch:int64 -> (unit,Error.t) result
val cancel : reservation -> (unit,Error.t) result
val reclaim : t -> completed_epoch:int64 -> (unit,Error.t) result
val snapshot : reservation -> (snapshot,Error.t) result
val payload : reservation -> (bytes option,Error.t) result
val live_slots : t -> int
val reservations : t -> snapshot list
val validate : Handle.device -> t -> (unit,Error.t) result
val destroy : t -> unit
