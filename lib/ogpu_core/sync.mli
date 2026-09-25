type fence
type event
type query_kind = Timestamp | Counter
type query_set
type description =
  | Signal_fence of int64 | Wait_fence of int64
  | Signal_event of int64 | Wait_event of int64
  | Resolve of { kind:query_kind; first:int; count:int; destination_offset:int64; completion_epoch:int64 }
val create_fence : Handle.device -> initial:int64 -> (fence,Error.t) result
val create_event : Handle.device -> initial:int64 -> (event,Error.t) result
val signal_fence : Handle.device -> fence -> int64 -> (description,Error.t) result
val wait_fence : Handle.device -> fence -> int64 -> (description,Error.t) result
val signal_event : Handle.device -> event -> int64 -> (description,Error.t) result
val wait_event : Handle.device -> event -> int64 -> (description,Error.t) result
val create_query_set : Handle.device -> supported:bool -> kind:query_kind -> count:int -> (query_set,Error.t) result
val resolve : Handle.device -> query_set -> destination:'a Handle.t -> destination_size:int64 -> first:int -> count:int -> destination_offset:int64 -> completion_epoch:int64 -> (description,Error.t) result
val destroy_fence : fence -> unit
val destroy_event : event -> unit
val destroy_query_set : query_set -> unit
val fence_value : fence -> int64
val event_value : event -> int64
