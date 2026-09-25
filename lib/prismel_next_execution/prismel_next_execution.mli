(** Isolated native Metal frame coordinator.  The public values deliberately
    contain no SDL or native handles. *)

type error_kind = Invalid_argument | Unsupported | Backend | Resource | Destroyed
type error = private { operation : string; kind : error_kind; message : string }
val pp_error : Format.formatter -> error -> unit

type configuration = {
  logical_width : int;
  logical_height : int;
  drawable_width : int;
  drawable_height : int;
  title : string;
  vsync : bool;
}
val default_configuration : configuration

type family = Scene_execution.pipeline_family = Scene2 | Scene2_textured | Scene3 | Scene3_points | Scene3_textured | Scene3_shadow |
  Scene3_stencil | Scene3_textured_stencil | Scene3_shadow_stencil | Ui
type blend = Ogpu.Pipeline.blend = Replace | Alpha | Add | Multiply | Screen | Subtract
type draw
type resource = Image of Prismel_next_resources.Image.t |
  Text of Prismel_next_resources.Text.t | Canvas of Prismel_next_resources.Canvas.t

(** Adopt an already prepared draw without exposing it again. Scene3 values are
    retained as a distinct family and never misrouted through a Scene2 pipeline. *)
val prepared_draw : family:family -> ?blend:blend ->
  ?texture:Scene_execution.sampled_texture ->
  ?auxiliary:Scene_execution.auxiliary_resource -> ?samples:int ->
  Scene_execution.draw -> draw

type t
val create : configuration -> (t,error) result
(* A true layerless native Metal target. It owns one long-lived device and
   pipeline coordinator until [destroy], without acquiring/presenting a window. *)
val create_offscreen : configuration -> (t,error) result
val lower_scene2 : t -> density:int -> resource:(int -> resource option) ->
  Scene_command.Render_ir.t -> (draw list,error) result
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
val show : t -> (unit,error) result
val hide : t -> (unit,error) result
val set_relative_mouse : t -> bool -> (unit,error) result
val set_cursor : t -> [`Default|`Horizontal_resize|`Vertical_resize] ->
  (unit,error) result
val set_text_input_area : t -> ((int * int * int * int) * int) option ->
  (unit,error) result
val visible : t -> (bool,error) result
val resize : t -> logical_width:int -> logical_height:int ->
  drawable_width:int -> drawable_height:int -> (unit,error) result
val step : ?clear:(float * float * float * float) -> t -> draw list ->
  (unit,error) result
val capture : t -> (bytes,error) result
val capture_into : t -> destination:bytes -> (unit,error) result

(** An offscreen execution's completed frame texture, on the device it leased
    (the presenting window's when one exists). A window execution samples a
    Canvas published from it directly; readback happens only for CPU access. *)
val offscreen_target : t -> (Ogpu.Backend.texture,error) result
val destroy : t -> (unit,error) result

(** A borrowed GPU: the active window's OGPU device (so Scene samples GPU
    film textures directly) or, without a window, a lazily created headless
    device shared by all leases. Every lease owns its own queue. Release it
    while SDL is alive; the headless device goes away with the last lease. *)
type gpu
val acquire_gpu : unit -> (gpu,error) result
val gpu_device : gpu -> Ogpu.Backend.device
val gpu_queue : gpu -> Ogpu.Backend.queue

(** True when the device is the presenting window's. *)
val gpu_shared : gpu -> bool
val release_gpu : gpu -> unit
module Private : sig
  val snapshot_count_for_test : t -> int
  type submission
  type batch
  (* Starts an isolated zero-copy Scene2 lowering transaction.  A later
      lowering or step failure releases every image snapshot owned by this
      submission without affecting another active submission. *)
  val begin_submission : t -> (submission,error) result
  val lower_scene2 : submission -> density:int ->
    resource:(int -> resource option) -> Scene_command.Render_ir.t ->
    (batch,error) result
  val lower_scene2_segment : submission -> identity:int64 -> version:int64 ->
    cacheable:bool -> density:int -> resource:(int -> resource option) ->
    Scene_command.Render_ir.t -> (batch,error) result
  (* Lowers PXUI instances into one [Ui] draw per batch. Texture ids resolve
     through [resource]; id 0 samples a white texel. *)
  val lower_ui : submission -> density:int ->
    resource:(int -> resource option) -> Scene_command.Ui_batch.t ->
    (batch,error) result
  (* Adopts already prepared non-Scene2 draws into this submission. *)
  val adopt_draws : submission -> draw list -> (batch,error) result
  (* Consumes the submission on either success or failure. *)
  val step : ?clear:(float * float * float * float) -> ?identity:string ->
    ?version:int64 -> submission ->
    batch list -> (unit,error) result
  val replay : ?clear:(float * float * float * float) -> identity:string ->
    version:int64 -> t -> (unit option,error) result
  (* Idempotently releases an unsubmitted transaction. *)
  val cancel : submission -> unit
  val retained_scene2_segment_stats : t -> int * int64 * int64
end
