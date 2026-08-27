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
val destroy : t -> (unit, Ogpu.Error.t) result
