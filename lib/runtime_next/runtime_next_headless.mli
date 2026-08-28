type t

val create :
  logical_width:int -> logical_height:int ->
  drawable_width:int -> drawable_height:int ->
  (t, Ogpu.Error.t) result
val render : t -> Scene_execution.draw list -> (bool, Ogpu.Error.t) result
val render_sampled_resources : t ->
  (Scene_execution.pipeline_family * Ogpu.Pipeline.blend *
   Scene_execution.sampled_texture option * Scene_execution.auxiliary_resource option *
   int * Scene_execution.draw) list -> (bool, Ogpu.Error.t) result
val resize : t -> logical_width:int -> logical_height:int ->
  drawable_width:int -> drawable_height:int -> (unit, Ogpu.Error.t) result
val read_pixels : t -> bytes_per_row:int -> (bytes, Ogpu.Error.t) result
val presented_pixels : t -> (bytes, Ogpu.Error.t) result
val sdl_drivers : t -> (string * string, Ogpu.Error.t) result
val backend_live_counts : t -> int * int * int * int * int
val backend_trace_stats : t -> int * int
val resource_stats : t -> int64 * int
val destroy : t -> (unit, Ogpu.Error.t) result
