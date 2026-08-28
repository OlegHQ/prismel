type target = Native
type t
type configuration = { target:target; logical_width:int; logical_height:int;
  drawable_width:int; drawable_height:int }
type facts = { title:string; logical_width:int; logical_height:int;
  drawable_width:int; drawable_height:int; position:(int*int) option;
  pixel_density:float; display_scale:float; refresh_rate:float option; vsync:bool }
type pacing = { frames:int64; presented:int64; last_presented:bool }
type stats = { frames:int64; presented:int64; logical_draws:int64;
  logical_passes:int64; logical_submissions:int64; uploaded_bytes:int64;
  cache_entries:int; gpu_timing_supported:bool; gpu_duration_seconds:float;
  gpu_sample_count:int64; retained_plan_builds:int64; retained_plan_hits:int64;
  retained_plan_misses:int64; retained_plan_evictions:int64;
  retained_plan_executions:int64; retained_plan_entries:int;
  retained_plan_capacity:int }
type diagnostics = { active:bool; cache_entries:int;
  release_queue_pending:int option; release_queue_live_handles:int option;
  release_queue_total_created:int64 option;
  release_queue_total_released:int64 option }
type family = Scene2 | Scene2_textured | Scene3 | Scene3_textured | Scene3_shadow |
  Scene3_stencil | Scene3_textured_stencil | Scene3_shadow_stencil
type blend = Replace | Alpha | Add | Multiply | Screen | Subtract
type prepared = {
  family : family;
  blend : blend;
  texture : Scene_execution.sampled_texture option;
  auxiliary : Scene_execution.auxiliary_resource option;
  samples : int;
  draw : Scene_execution.draw;
}
val target_of_string : string -> (target,string) result
val select_with : (string -> string option) -> (target,string) result
val selected : unit -> (target,string) result
val create : configuration -> (t,Ogpu.Error.t) result
val target : t -> target
val is_native : t -> bool
val facts : t -> (facts,Ogpu.Error.t) result
val pacing : t -> (pacing,Ogpu.Error.t) result
val stats : t -> (stats,Ogpu.Error.t) result
val diagnostics : t -> diagnostics
(** Read-only teardown diagnostics for the native Metal target. *)
val native_release_queue : unit -> (int * int * int64 * int64) option
(** [(pending, live_handles, total_created, total_released)] when the typed
    Metal counter source is available. *)
val render : t -> Scene_execution.draw list -> (bool,Ogpu.Error.t) result
val render_prepared : t -> prepared list -> (bool,Ogpu.Error.t) result
val resize : t -> logical_width:int -> logical_height:int -> drawable_width:int ->
  drawable_height:int -> (unit,Ogpu.Error.t) result
val capture : t -> bytes_per_row:int -> (bytes,Ogpu.Error.t) result
val set_title : t -> string -> (unit,Ogpu.Error.t) result
val set_position : t -> x:int -> y:int -> (unit,Ogpu.Error.t) result
val center : t -> (unit,Ogpu.Error.t) result
val set_bordered : t -> bool -> (unit,Ogpu.Error.t) result
val set_resizable : t -> bool -> (unit,Ogpu.Error.t) result
val set_always_on_top : t -> bool -> (unit,Ogpu.Error.t) result
val set_fullscreen : t -> bool -> (unit,Ogpu.Error.t) result
val show : t -> (unit,Ogpu.Error.t) result
val hide : t -> (unit,Ogpu.Error.t) result
val visible : t -> (bool,Ogpu.Error.t) result
val minimize : t -> (unit,Ogpu.Error.t) result
val maximize : t -> (unit,Ogpu.Error.t) result
val restore : t -> (unit,Ogpu.Error.t) result
val destroy : t -> (unit,Ogpu.Error.t) result
