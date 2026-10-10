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
type stats = {   logical_draws:int64;
  logical_passes:int64;
  pipeline_cache_entries:int;
  uploaded_bytes:int64;  gpu_duration_seconds:float;
    retained_plan_hits:int64;
  retained_plan_misses:int64;

  sun_shadow_passes:int64; (** World sun map renders (Scene3.with_world). *) }

val zero_stats : stats

type frame_facts = { logical_width:int; logical_height:int;
  drawable_width:int; drawable_height:int; pixel_scale_x:float; pixel_scale_y:float }

(** An offscreen target has no [position] or [refresh_rate], never vsyncs,
    and reports its drawable/logical ratio as both density and display scale. *)
type presentation_facts = {
   logical_width : int; logical_height : int;
  drawable_width : int; drawable_height : int;
  pixel_density : float;

}
val create : ?vsync:bool -> ?hidden:bool -> ?high_density:bool -> ?title:string ->
  width:int -> height:int -> unit -> (t, Ogpu.Error.t) result
(** [high_density] (default true) asks for a drawable at the display's native density; false
    keeps the drawable at the logical size, so a capture is the same bytes on every display. *)

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
val resize : t -> width:int -> height:int ->
  (unit, Ogpu.Error.t) result
val read_pixels : t -> bytes_per_row:int -> (bytes, Ogpu.Error.t) result
val stats : t -> stats
val frame_facts : t -> frame_facts
val map_logical_rect : frame_facts -> int * int * int * int ->
  int * int * int * int

(** Cached presentation facts, requeried when the drawable changes and after
    resize or show. *)
val presentation_facts : t -> (presentation_facts, Ogpu.Error.t) result

val set_resizable : t -> bool -> (unit, Ogpu.Error.t) result
val set_window_background : t -> float * float * float -> (unit, Ogpu.Error.t) result
(** The native window's own background (sRGB, 0..1): what the title bar shows,
    since a Rays window hides its title and keeps only the traffic lights. *)

val set_relative_mouse : t -> bool -> (unit, Ogpu.Error.t) result
(** Hide and capture the pointer, reporting relative motion (fly cameras). *)

val set_cursor : t -> [`Default|`Horizontal_resize|`Vertical_resize|`Text] ->
  (unit, Ogpu.Error.t) result

(** Text input runs only while a text field has focus: [Some (region, cursor)]
    (logical points) starts it and places the input method there, [None] stops
    it. Repeating the same answer costs no SDL call. *)
val set_text_input : t -> ((int * int * int * int) * int) option ->
  (unit, Ogpu.Error.t) result

(** Tell a window target that SDL announced a size or density change, so the
    next frame re-reads its facts. The window is not polled between
    announcements. *)
val window_changed : t -> unit

val show : t -> (unit, Ogpu.Error.t) result

(** Native file dialogs. [show_dialog] returns at once with the dialog's id;
    the outcome arrives as a [Runtime_input.Dialog_closed] with that id, in
    the next event poll on the initial domain. [pattern] lists extensions
    separated by semicolons ("png;jpg"), or "*". At most 8 dialogs are open at
    once; a ninth is an error. *)
type dialog_kind = Open_file | Open_files | Save_file | Open_folder
type dialog_filter = { name : string; pattern : string }
val show_dialog : t -> ?filters:dialog_filter list -> ?default_location:string ->
  dialog_kind -> (int, Ogpu.Error.t) result

(** Shown and neither minimized nor covered. SDL announces the start of
    occlusion and not its end: ask once per frame while hidden. *)
val visible : t -> (bool, Ogpu.Error.t) result
val destroy : t -> (unit, Ogpu.Error.t) result
module Private : sig
  (** One announcement bit per window: [announce] when SDL says the size or
      density changed, [refresh flag query] runs [query] once and only if a
      change was announced since the last refresh. *)
  module Change_flag : sig
    type t
    val create : unit -> t
    val announce : t -> unit
    val refresh : t -> (unit -> 'a) -> 'a option
  end

  (** The SDL window of a window target, for qualification tests that change
      its size behind the runtime's back. *)
  val window_handle : t -> Sdl3.Window.t option

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
