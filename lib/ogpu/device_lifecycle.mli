type phase = Surface_frames | Submissions | Descriptor_arenas | Transfer_rings | Caches | Resources
type policy = Drain | Abandon
type reason = Device_lost | Shutdown
type failure = { phase:phase; label:string; error:Error.t }
type report = { reason:reason; policy:policy; callbacks:int; failures:failure list }
type t

val create : device:Handle.device -> capacity:int -> (t,Error.t) result
val register : Handle.device -> t -> phase:phase -> label:string ->
  (policy -> (unit,Error.t) result) -> (unit,Error.t) result
val transition : t -> reason:reason -> policy:policy -> (report,Error.t) result
val terminal_report : t -> report option
val registered_count : t -> int
val metadata_count : t -> int
val destroy : t -> (unit,Error.t) result
