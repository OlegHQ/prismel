type t
type stats = { pipeline_cache_entries:int; mesh_cache_entries:int;
  uploaded_bytes:int64 }
type frame_facts = { logical_width:int; logical_height:int;
  drawable_width:int; drawable_height:int; pixel_scale_x:float; pixel_scale_y:float }
val create : width:int -> height:int -> (t, Ogpu.Error.t) result
val render : ?clear:(float * float * float * float) -> t ->
  Scene_execution.draw list -> (bool, Ogpu.Error.t) result
val render_sampled_resources : ?clear:(float * float * float * float) -> t ->
  (Scene_execution.pipeline_family * Ogpu.Pipeline.blend *
   Scene_execution.sampled_texture option * Scene_execution.auxiliary_resource option *
   int * Scene_execution.draw) list -> (bool, Ogpu.Error.t) result
val resize : t -> width:int -> height:int -> (unit, Ogpu.Error.t) result
val read_pixels : t -> bytes_per_row:int -> (bytes, Ogpu.Error.t) result
val stats : t -> stats
val frame_facts : t -> frame_facts
val map_logical_rect : frame_facts -> int * int * int * int ->
  int * int * int * int
val handle_window_event : t -> Sdl3.Event.t -> (bool, Ogpu.Error.t) result
val destroy : t -> (unit, Ogpu.Error.t) result
