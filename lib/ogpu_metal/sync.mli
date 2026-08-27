type fence
type event
type query_set

val create_fence : Device.t -> initial:int64 -> (fence, Ogpu.Error.t) result
val signal_fence : Device.t -> fence -> int64 -> (Ogpu.Sync.description, Ogpu.Error.t) result
val wait_fence : Device.t -> fence -> int64 -> (Ogpu.Sync.description, Ogpu.Error.t) result
val destroy_fence : fence -> (unit, Ogpu.Error.t) result

val create_event : Device.t -> initial:int64 -> (event, Ogpu.Error.t) result
val signal_event : Device.t -> event -> int64 -> (Ogpu.Sync.description, Ogpu.Error.t) result
val wait_event : Device.t -> event -> int64 -> (Ogpu.Sync.description, Ogpu.Error.t) result
val destroy_event : event -> (unit, Ogpu.Error.t) result

val create_query_set : Device.t -> kind:Ogpu.Sync.query_kind -> count:int ->
  (query_set, Ogpu.Error.t) result
val execute_query_pass : Device.t -> query_set -> first:int -> count:int ->
  destination:Buffer.t -> destination_offset:int64 -> completion_epoch:int64 ->
  (Ogpu.Query_pass.description, Ogpu.Error.t) result
val query_supported : query_set -> bool
val destroy_query_set : query_set -> (unit, Ogpu.Error.t) result
