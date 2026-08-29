(** Isolated native Metal frame coordinator.  The public values deliberately
    contain no SDL or native handles. *)

type error_kind = Invalid_argument | Unsupported | Backend | Resource | Destroyed
type error = private { operation : string; kind : error_kind; message : string }
val pp_error : Format.formatter -> error -> unit

type timing = Fixed of float | Variable
type configuration = {
  logical_width : int;
  logical_height : int;
  drawable_width : int;
  drawable_height : int;
  title : string;
  timing : timing;
  max_events : int;
  max_file_bytes : int;
}
val default_configuration : configuration

type mouse_button = Left | Middle | Right | X1 | X2
type modifier = Shift | Control | Alt | Meta | Num_lock | Caps_lock | Scroll_lock
type key = { name : string; modifiers : modifier list; repeat : bool }
type event =
  | Pointer_moved of float * float
  | Pointer_pressed of mouse_button * float * float
  | Pointer_released of mouse_button * float * float
  | Pointer_cancelled of mouse_button
  | Wheel of float * float
  | Key_pressed of key | Key_released of key
  | Text_input of string
  | Text_editing of { text : string; start : int; length : int }
  | Focus_lost | Focus_gained | Visibility_changed of bool | Quit
  | Resized of int * int
  | File_dropped of { name : string; contents : bytes option }

type facts = {
  frame : int64;
  time : float;
  dt : float;
  logical_width : int;
  logical_height : int;
  drawable_width : int;
  drawable_height : int;
  pixel_scale : float;
  events : event list;
  pointer : float * float;
  mouse_delta : float * float;
  wheel_delta : float * float;
  dropped_events : int;
}

type family = Scene2 | Scene2_textured | Scene3 | Scene3_textured | Scene3_shadow |
  Scene3_stencil | Scene3_textured_stencil | Scene3_shadow_stencil
type blend = Replace | Alpha | Add | Multiply | Screen | Subtract
type draw
type resource = Image of Prismel_next_resources.Image.t |
  Text of Prismel_next_resources.Text.t | Canvas of Prismel_next_resources.Canvas.t

(** Lower target-neutral geometry commands. Image and glyph commands require
    resource binding and are rejected atomically in this first staging slice. *)
val scene2_ir : Scene_command.Render_ir.t -> (draw list, error) result

(** Lower already validated renderer-neutral native Scene2 commands. *)
val scene2_commands : Scene_execution.Scene2_command.t array ->
  (draw list, error) result

(** Adopt an already prepared draw without exposing it again. Scene3 values are
    retained as a distinct family and never misrouted through a Scene2 pipeline. *)
val prepared_draw : family:family -> ?blend:blend ->
  ?texture:Scene_execution.sampled_texture ->
  ?auxiliary:Scene_execution.auxiliary_resource -> ?samples:int ->
  Scene_execution.draw -> draw

type t
val create : configuration -> (t,error) result
val assets : t -> Prismel_next_resources.Assets.t
val lower_scene2 : t -> density:int -> resource:(int -> resource option) ->
  Scene_command.Render_ir.t -> (draw list,error) result
val snapshot_cache_entries : t -> int
val scene2_geometry_cache_entries : t -> int * int
type stats = Runtime_next_orchestrator.stats = { frames:int64; presented:int64;
  logical_draws:int64; logical_passes:int64; logical_submissions:int64;
  uploaded_bytes:int64; cache_entries:int; gpu_timing_supported:bool;
  gpu_duration_seconds:float; gpu_sample_count:int64;
  retained_plan_builds:int64; retained_plan_hits:int64;
  retained_plan_misses:int64; retained_plan_evictions:int64;
  retained_plan_executions:int64; retained_plan_entries:int;
  retained_plan_capacity:int }
val stats : t -> (stats,error) result
type presentation_facts = {
  title : string;
  logical_width : int;
  logical_height : int;
  drawable_width : int;
  drawable_height : int;
  position : (int * int) option;
  pixel_density : float;
  display_scale : float;
  refresh_rate : float option;
  vsync : bool;
}
(* Read-only production-window facts for native qualification tooling. *)
val presentation_facts : t -> (presentation_facts,error) result
type diagnostics = { active:bool; resource_count:int; cache_entries:int;
  release_queue_pending:int option; release_queue_live_handles:int option;
  release_queue_total_created:int64 option;
  release_queue_total_released:int64 option }
val diagnostics : t -> diagnostics
(* Actual coordinator, owned-resource, renderer-cache, and native release
   queue state.  This remains readable after [destroy]. *)
val native_release_queue : unit -> (int * int * int64 * int64) option
val show : t -> (unit,error) result
val hide : t -> (unit,error) result
val visible : t -> (bool,error) result
val push_event : t -> event -> (unit,error) result
val resize : t -> logical_width:int -> logical_height:int ->
  drawable_width:int -> drawable_height:int -> (unit,error) result
val step : ?clear:(float * float * float * float) -> t -> draw list ->
  (facts,error) result
val capture : t -> (bytes,error) result
val destroy : t -> (unit,error) result
module Private : sig
  val draw_family_blend : draw -> family * blend
end

(** Always destroys in resources -> coordinator -> target/extensions order.
    [on_stop] runs while resources and the target are still alive. *)
val run : configuration -> (t -> ('a,error) result) ->
  on_stop:(t -> (unit,error) result) -> ('a,error) result
