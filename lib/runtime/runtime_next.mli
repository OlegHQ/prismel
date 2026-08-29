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
val create : ?vsync:bool -> ?hidden:bool -> ?title:string ->
  width:int -> height:int -> unit -> (t, Ogpu.Error.t) result
val render : ?clear:(float * float * float * float) -> t ->
  Scene_execution.draw list -> (bool, Ogpu.Error.t) result
val render_sampled_resources : ?after_prepare:(unit -> unit) -> ?clear:(float * float * float * float) -> t ->
  (Scene_execution.pipeline_family * Ogpu.Pipeline.blend *
   Scene_execution.sampled_texture option * Scene_execution.auxiliary_resource option *
   int * Scene_execution.draw) list -> (bool, Ogpu.Error.t) result
val render_prepared_sampled_resources :
  ?after_prepare:(unit -> unit) -> ?clear:(float * float * float * float) -> identity:string -> version:int64 -> t ->
  (Scene_execution.pipeline_family * Ogpu.Pipeline.blend *
   Scene_execution.sampled_texture option * Scene_execution.auxiliary_resource option *
   int * Scene_execution.draw) list -> (bool, Ogpu.Error.t) result
val resize : t -> width:int -> height:int -> (unit, Ogpu.Error.t) result
val read_pixels : t -> bytes_per_row:int -> (bytes, Ogpu.Error.t) result
val read_pixels_into : t -> bytes_per_row:int -> destination:bytes ->
  (unit, Ogpu.Error.t) result
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
type offscreen
val create_offscreen : logical_width:int -> logical_height:int ->
  width:int -> height:int -> (offscreen,Ogpu.Error.t) result
val render_offscreen : ?after_prepare:(unit -> unit) -> ?clear:(float*float*float*float) -> offscreen ->
  (Scene_execution.pipeline_family * Ogpu.Pipeline.blend *
   Scene_execution.sampled_texture option * Scene_execution.auxiliary_resource option *
   int * Scene_execution.draw) list -> (bool,Ogpu.Error.t) result
val replay_prepared_sampled_resources :
  ?clear:(float * float * float * float) -> identity:string -> version:int64 -> t ->
  ((bool * int) option, Ogpu.Error.t) result
val render_offscreen_prepared : ?after_prepare:(unit -> unit) -> ?clear:(float*float*float*float) ->
  identity:string -> version:int64 -> offscreen ->
  (Scene_execution.pipeline_family * Ogpu.Pipeline.blend *
   Scene_execution.sampled_texture option * Scene_execution.auxiliary_resource option *
   int * Scene_execution.draw) list -> (bool,Ogpu.Error.t) result
val read_offscreen : offscreen -> bytes_per_row:int -> (bytes,Ogpu.Error.t) result
val read_offscreen_into : offscreen -> bytes_per_row:int -> destination:bytes ->
  (unit,Ogpu.Error.t) result
val resize_offscreen : offscreen -> logical_width:int -> logical_height:int ->
  width:int -> height:int -> (unit,Ogpu.Error.t) result
val offscreen_stats : offscreen -> stats
val offscreen_facts : offscreen -> frame_facts
val destroy_offscreen : offscreen -> (unit,Ogpu.Error.t) result
module Private : sig
  val scene2_textured_direct : string
  val scene2_textured_argument : string
  val scale_draws : frame_facts -> Scene_execution.draw list -> Scene_execution.draw list
  val scale_sampled_resources : frame_facts ->
    (Scene_execution.pipeline_family * Ogpu.Pipeline.blend *
     Scene_execution.sampled_texture option * Scene_execution.auxiliary_resource option *
     int * Scene_execution.draw) list ->
    (Scene_execution.pipeline_family * Ogpu.Pipeline.blend *
     Scene_execution.sampled_texture option * Scene_execution.auxiliary_resource option *
     int * Scene_execution.draw) list
end
