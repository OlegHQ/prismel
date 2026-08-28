type t
type stats = { pipeline_cache_entries:int; mesh_cache_entries:int;
  uploaded_bytes:int64; gpu_timing_supported:bool; gpu_duration_seconds:float;
  gpu_sample_count:int64; retained_plan_builds:int64; retained_plan_hits:int64;
  retained_plan_misses:int64; retained_plan_evictions:int64;
  retained_plan_executions:int64; retained_plan_entries:int;
  retained_plan_capacity:int }
type frame_facts = { logical_width:int; logical_height:int;
  drawable_width:int; drawable_height:int; pixel_scale_x:float; pixel_scale_y:float }
type window_facts = {
  title : string; logical_width : int; logical_height : int;
  drawable_width : int; drawable_height : int; position : int * int;
  pixel_density : float; display_scale : float; refresh_rate : float option;
  vsync : bool;
}
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
val window_facts : t -> vsync:bool -> (window_facts, Ogpu.Error.t) result
val set_title : t -> string -> (unit, Ogpu.Error.t) result
val set_position : t -> x:int -> y:int -> (unit, Ogpu.Error.t) result
val center : t -> (unit, Ogpu.Error.t) result
val set_bordered : t -> bool -> (unit, Ogpu.Error.t) result
val set_resizable : t -> bool -> (unit, Ogpu.Error.t) result
val set_always_on_top : t -> bool -> (unit, Ogpu.Error.t) result
val set_fullscreen : t -> bool -> (unit, Ogpu.Error.t) result
val show : t -> (unit, Ogpu.Error.t) result
val hide : t -> (unit, Ogpu.Error.t) result
val visible : t -> (bool, Ogpu.Error.t) result
val minimize : t -> (unit, Ogpu.Error.t) result
val maximize : t -> (unit, Ogpu.Error.t) result
val restore : t -> (unit, Ogpu.Error.t) result
val destroy : t -> (unit, Ogpu.Error.t) result
module Private : sig
  val scene2_textured_direct : string
  val scene2_textured_argument : string
end
