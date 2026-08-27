type heap
type allocation

val create : Device.t -> Ogpu.Memory.descriptor -> (heap, Ogpu.Error.t) result
val create_sparse : Device.t -> Ogpu.Memory.descriptor -> (heap, Ogpu.Error.t) result
val allocate : Device.t -> heap -> size:int64 -> alignment:int64 ->
  (allocation, Ogpu.Error.t) result
val interval : allocation -> Ogpu.Memory.interval
val write_bytes : Device.t -> allocation -> offset:int64 -> bytes ->
  (unit, Ogpu.Error.t) result
val read_bytes : Device.t -> allocation -> offset:int64 -> length:int ->
  (bytes, Ogpu.Error.t) result
val begin_alias : Device.t -> allocation -> (unit, Ogpu.Error.t) result
val end_alias : Device.t -> allocation -> (unit, Ogpu.Error.t) result
val free : allocation -> (unit, Ogpu.Error.t) result
val live_allocations : heap -> int
val destroyed : heap -> bool
val destroy : heap -> (unit, Ogpu.Error.t) result
