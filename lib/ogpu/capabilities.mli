type limits =
  { max_buffer_size:int64; max_texture_dimension_2d:int
  ; max_bind_groups:int; max_sample_count:int }
type t = { limits:limits; ray_tracing:bool; metal_fx:bool }
val minimum_m1 : t
val validate : t -> (unit,Error.t) result
