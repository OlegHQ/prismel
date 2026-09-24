type triangle_plan =
  { offset : int64; length : int64; vertex_stride : int; vertex_count : int }
type t

val plan_triangle : ray_tracing:bool -> buffer_size:int64 -> offset:int64 ->
  length:int64 -> vertex_stride:int -> vertex_count:int ->
  (triangle_plan, Ogpu.Error.t) result
val validate_scratch_plan : buffer_size:int64 -> offset:int64 -> required:int64 ->
  (unit, Ogpu.Error.t) result
val create_triangle : Device.t -> vertices:Buffer.t -> offset:int64 -> length:int64 ->
  vertex_stride:int -> vertex_count:int -> allow_refit:bool ->
  (t, Ogpu.Error.t) result
val build : Device.t -> t -> scratch:Buffer.t -> scratch_offset:int64 ->
  (Ogpu.Acceleration.description, Ogpu.Error.t) result
val refit : Device.t -> t -> scratch:Buffer.t -> scratch_offset:int64 ->
  (Ogpu.Acceleration.description, Ogpu.Error.t) result
val copy : Device.t -> t -> (t * Ogpu.Acceleration.description, Ogpu.Error.t) result
val compact : Device.t -> t -> (Ogpu.Acceleration.description, Ogpu.Error.t) result
val destroy : t -> (unit, Ogpu.Error.t) result
