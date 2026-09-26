(** One native render target: a presenting SDL3/Metal window or an owned
    offscreen texture. Rendering, readback, resize, stats, and presentation
    facts work on both; window operations return [Unsupported] offscreen. *)
type t
val clipboard_set_text : string -> (unit, Ogpu.Error.t) result
val clipboard_get_text : unit -> (string, Ogpu.Error.t) result

(** The target's OGPU device, shared with GPU film producers such as the path
    tracer so Scene can sample their textures without staging. *)
val device : t -> (Ogpu.Backend.device,Ogpu.Error.t) result

(** The completed frame's texture on the target's device. *)
val target : t -> (Ogpu.Backend.texture,Ogpu.Error.t) result

(** One record for window and offscreen targets. [frames] counts successful
    renders and replays; [presented] those that reached the display. *)
type stats = { frames:int64; presented:int64; logical_draws:int64;
  logical_passes:int64; logical_submissions:int64;
  pipeline_cache_entries:int; mesh_cache_entries:int;
  uploaded_bytes:int64; gpu_timing_supported:bool; gpu_duration_seconds:float;
  gpu_sample_count:int64; retained_plan_builds:int64; retained_plan_hits:int64;
  retained_plan_misses:int64; retained_plan_evictions:int64;
  retained_plan_executions:int64; retained_plan_entries:int;
  retained_plan_capacity:int }

val zero_stats : stats

type frame_facts = { logical_width:int; logical_height:int;
  drawable_width:int; drawable_height:int; pixel_scale_x:float; pixel_scale_y:float }

(** An offscreen target has no [position] or [refresh_rate], never vsyncs,
    and reports its drawable/logical ratio as both density and display scale. *)
type presentation_facts = {
  title : string; logical_width : int; logical_height : int;
  drawable_width : int; drawable_height : int; position : (int * int) option;
  pixel_density : float; display_scale : float; refresh_rate : float option;
  vsync : bool;
}
val create : ?vsync:bool -> ?hidden:bool -> ?title:string ->
  width:int -> height:int -> unit -> (t, Ogpu.Error.t) result

(** A layerless target that never acquires or presents. [?device] borrows a
    live OGPU device (normally the presenting window's, see [device]) so the
    window can sample it without readback; a borrowed device is never
    destroyed here. *)
val create_offscreen : ?device:Ogpu.Backend.device -> ?title:string ->
  logical_width:int -> logical_height:int -> width:int -> height:int -> unit ->
  (t,Ogpu.Error.t) result
val render : ?clear:(float * float * float * float) -> t ->
  Scene_execution.draw list -> (bool, Ogpu.Error.t) result
val render_sampled_resources : ?after_prepare:(unit -> unit) -> ?clear:(float * float * float * float) -> t ->
  Scene_execution.sampled_draw list -> (bool, Ogpu.Error.t) result
val render_prepared_sampled_resources :
  ?after_prepare:(unit -> unit) -> ?clear:(float * float * float * float) -> identity:string -> version:int64 -> t ->
  Scene_execution.sampled_draw list -> (bool, Ogpu.Error.t) result
val replay_prepared_sampled_resources :
  ?clear:(float * float * float * float) -> identity:string -> version:int64 -> t ->
  (bool option, Ogpu.Error.t) result

(** Resizes to [width]x[height] logical points. A window's drawable follows
    its display, so [?drawable] is rejected there; an offscreen target uses
    [?drawable] pixels, 1x by default. *)
val resize : ?drawable:int * int -> t -> width:int -> height:int ->
  (unit, Ogpu.Error.t) result
val read_pixels : t -> bytes_per_row:int -> (bytes, Ogpu.Error.t) result
val read_pixels_into : t -> bytes_per_row:int -> destination:bytes ->
  (unit, Ogpu.Error.t) result
val stats : t -> stats
val frame_facts : t -> frame_facts
val map_logical_rect : frame_facts -> int * int * int * int ->
  int * int * int * int

(** Cached presentation facts, requeried when the drawable changes and after
    resize or show. *)
val presentation_facts : t -> (presentation_facts, Ogpu.Error.t) result

val set_resizable : t -> bool -> (unit, Ogpu.Error.t) result
val set_relative_mouse : t -> bool -> (unit, Ogpu.Error.t) result
(** Hide and capture the pointer, reporting relative motion (fly cameras). *)

val set_cursor : t -> [`Default|`Horizontal_resize|`Vertical_resize] ->
  (unit, Ogpu.Error.t) result
val set_text_input_area : t -> ((int * int * int * int) * int) option ->
  (unit, Ogpu.Error.t) result

val show : t -> (unit, Ogpu.Error.t) result
val hide : t -> (unit, Ogpu.Error.t) result
val visible : t -> (bool, Ogpu.Error.t) result
val restore : t -> (unit, Ogpu.Error.t) result
val destroy : t -> (unit, Ogpu.Error.t) result
module Private : sig
  val scale_draws : frame_facts -> Scene_execution.draw list -> Scene_execution.draw list
  val scale_sampled_resources : frame_facts ->
    Scene_execution.sampled_draw list -> Scene_execution.sampled_draw list
  type scaled_cache
  val new_scaled_cache : unit -> scaled_cache

  (** [scale_sampled_resources] memoized on the physical identity of the input
      list and facts: a retained scene passes the same list every frame. *)
  val scale_sampled_cached : scaled_cache -> frame_facts ->
    Scene_execution.sampled_draw list -> Scene_execution.sampled_draw list
end
