type format = R8_unorm | Rgba8_unorm | Bgra8_unorm | Rgba16_float | Depth32_float | Stencil8
type memory = Device_local | Shared
type t

val create : Device.t -> memory:memory -> format:format ->
  ?view_formats:format list -> Ogpu_core.Types.texture_descriptor ->
  (t, Ogpu_core.Error.t) result
val create_in_heap : Device.t -> memory:memory -> Metal.Heap.t -> offset:int64 -> format:format ->
  Ogpu_core.Types.texture_descriptor -> (t, Ogpu_core.Error.t) result

(** An initially unmapped texture inside a sparse heap. *)
val create_sparse : Device.t -> Metal.Heap.t -> format:format ->
  Ogpu_core.Types.texture_descriptor -> (t, Ogpu_core.Error.t) result

(** Size and alignment the texture needs inside a heap. *)
val placement : Device.t -> memory:memory -> format:format -> Ogpu_core.Types.texture_descriptor ->
  (int64 * int64, Ogpu_core.Error.t) result
val create_view : Device.t -> t -> format:format -> base_mip:int ->
  mip_count:int -> base_slice:int -> slice_count:int -> (t, Ogpu_core.Error.t) result
val descriptor : Device.t -> t -> (Ogpu_core.Types.texture_descriptor, Ogpu_core.Error.t) result
val format : Device.t -> t -> (format, Ogpu_core.Error.t) result
val read_bytes : Device.t -> t -> mip_level:int -> bytes_per_row:int ->
  (bytes, Ogpu_core.Error.t) result
val read_bytes_into : Device.t -> t -> mip_level:int -> bytes_per_row:int ->
  destination:bytes -> (unit, Ogpu_core.Error.t) result
val write_bytes : Device.t -> t -> mip_level:int -> bytes_per_row:int -> bytes ->
  (unit, Ogpu_core.Error.t) result
val destroy : t -> (unit, Ogpu_core.Error.t) result

module Private : sig
  val metal : t -> Metal.Texture.t
  val retain_submission : t -> (unit,Ogpu_core.Error.t) result
  val release_submission : t -> unit
end
