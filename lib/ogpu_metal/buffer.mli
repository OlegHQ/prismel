type memory = Device_local | Shared | Upload | Readback
type t

val create : Device.t -> memory:memory -> Ogpu.Types.buffer_descriptor ->
  (t, Ogpu.Error.t) result
val id : t -> int64
val generation : t -> int64
val device_id : t -> int64
val descriptor : Device.t -> t -> (Ogpu.Types.buffer_descriptor, Ogpu.Error.t) result
val memory : Device.t -> t -> (memory, Ogpu.Error.t) result
val destroyed : t -> bool
val write_bytes : Device.t -> t -> dst_offset:int64 -> bytes -> (unit,Ogpu.Error.t) result
val read_bytes : Device.t -> t -> offset:int64 -> length:int -> (bytes,Ogpu.Error.t) result
val destroy : t -> (unit, Ogpu.Error.t) result

module Private : sig
  val metal : t -> Metal.Buffer.t
  val resource_handle : t -> unit Ogpu.Handle.t
end
