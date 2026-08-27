type t
type receipt = { id:int64; commands:Command.description array }
val create : ?max_frames:int -> Handle.device -> (t,Error.t) result
val submit : t -> Command.t -> resources:'a Handle.t list -> (receipt,Error.t) result
val complete_through : t -> int64 -> (unit,Error.t) result
val drain : t -> unit
val lose_device : t -> unit
val in_flight : t -> int
val retained_resource_count : t -> int
val completed_epoch : t -> int64
val pending_descriptions : t -> (int64 * Command.description array) array
