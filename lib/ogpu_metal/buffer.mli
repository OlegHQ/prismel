type memory = Device_local | Shared | Upload | Readback
type t

val create : Device.t -> memory:memory -> Ogpu_core.Types.buffer_descriptor ->
  (t, Ogpu_core.Error.t) result
val create_in_heap : Device.t -> memory:memory -> Metal.Heap.t -> offset:int64 ->
  Ogpu_core.Types.buffer_descriptor -> (t, Ogpu_core.Error.t) result
val generation : t -> int64
val device_id : t -> int64
val descriptor : Device.t -> t -> (Ogpu_core.Types.buffer_descriptor, Ogpu_core.Error.t) result
val memory : Device.t -> t -> (memory, Ogpu_core.Error.t) result
val write_bytes : Device.t -> t -> dst_offset:int64 -> bytes -> (unit,Ogpu_core.Error.t) result
val read_bytes : Device.t -> t -> offset:int64 -> length:int -> (bytes,Ogpu_core.Error.t) result
val destroy : t -> (unit, Ogpu_core.Error.t) result

module Private : sig
  val metal : t -> Metal.Buffer.t
  val resource_handle : t -> unit Ogpu_core.Handle.t
  val retain_submission : t -> (unit,Ogpu_core.Error.t) result
  val retain_for : commands:int64 -> t -> (bool,Ogpu_core.Error.t) result
  val release_submission : t -> unit
end
