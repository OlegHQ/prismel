type format = R8_unorm | Rgba8_unorm | Bgra8_unorm | Rgba16_float | Depth32_float
type memory = Device_local | Shared
type t

val create : Device.t -> memory:memory -> format:format ->
  ?view_formats:format list -> Ogpu.Types.texture_descriptor ->
  (t, Ogpu.Error.t) result
val create_view : Device.t -> t -> format:format -> base_mip:int ->
  mip_count:int -> base_slice:int -> slice_count:int -> (t, Ogpu.Error.t) result
val id : t -> int64
val generation : t -> int64
val device_id : t -> int64
val descriptor : Device.t -> t -> (Ogpu.Types.texture_descriptor, Ogpu.Error.t) result
val format : Device.t -> t -> (format, Ogpu.Error.t) result
val destroyed : t -> bool
val read_bytes : Device.t -> t -> mip_level:int -> bytes_per_row:int ->
  (bytes, Ogpu.Error.t) result
val write_bytes : Device.t -> t -> mip_level:int -> bytes_per_row:int -> bytes ->
  (unit, Ogpu.Error.t) result
val destroy : t -> (unit, Ogpu.Error.t) result
