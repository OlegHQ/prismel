(** Compact creative-coding UI toolkit for Prismel.

    A canvas owns widgets, lays them out vertically, draws them with Prismel,
    and translates Prismel mouse events into named UI changes. Rendering and
    hit testing share one logical-point layout. *)

type change =
  | Clicked of string
  | Toggled of string * bool
  | Slid of string * float
  | Int_slid of string * int
  | Text_changed of string * string
  | Selected of string * string
  | Ranged of string * float * float
  | Moved2 of string * float * float

type t

type theme = {
  panel : Prismel.Color.t;
  foreground : Prismel.Color.t;
  control : Prismel.Color.t;
  input : Prismel.Color.t;
  track : Prismel.Color.t;
  accent : Prismel.Color.t;
}

val default_theme : theme
val create :
  ?x:int ->
  ?y:int ->
  ?width:int ->
  ?row_height:int ->
  ?padding:int ->
  ?theme:theme ->
  ?font:Prismel.Font.t ->
  ?font_size:int ->
  ?max_height:int ->
  unit ->
  t
(** Create a graphite/cyan panel using Prismel's installed system UI font by
    default. [font_size] is a logical point size; [font] overrides the default
    font resource. [max_height] clips overflowing rows and enables vertical
    wheel/trackpad scrolling while the pointer is over the panel. *)

val label : text:string -> t -> t
(* Group controls beneath a clickable, persistent disclosure header.
    Collapsed children retain their values and do not participate in layout or
    hit testing. Accordions may be nested. *)
val accordion :
  name:string -> label:string -> expanded:bool -> (t -> t) -> t -> t
val button : name:string -> label:string -> t -> t
val toggle : name:string -> label:string -> value:bool -> t -> t
val slider :
  name:string -> label:string -> min:float -> max:float -> value:float -> t -> t
(** Slider bounds define its soft drag range. The initial value, programmatic
    setters, persistence, and inline numeric entry may remain outside it. *)

(** [int_slider] stores, displays, emits, and persists integers without a
    float-rounding adapter. Its bounds are likewise a soft drag range. *)
val int_slider :
  name:string -> label:string -> min:int -> max:int -> value:int -> t -> t
val text_field : name:string -> label:string -> value:string -> t -> t
val choice :
  name:string -> label:string -> options:string list -> selected:int -> t -> t
val range :
  name:string ->
  label:string ->
  min:float ->
  max:float ->
  low:float ->
  high:float ->
  t ->
  t
val xy :
  name:string ->
  label:string ->
  x_range:float * float ->
  y_range:float * float ->
  value:float * float ->
  t ->
  t
(** Functional, pipeline-friendly widget builders. *)

val update : ?time:float -> t -> Prismel.Event.t list -> t * change list
(** Return an updated UI value and ordered changes without mutating the input.
    Buttons activate on release-inside. Sliders, ranges, and XY pads capture
    the pointer and emit continuous, clamped changes while dragging. Integer
    sliders snap before emitting [Int_slid]. Typed slider values are finite but
    may exceed the soft drag range. A bounded panel consumes vertical scrolling
    while the tracked pointer is inside it. Passing logical [time] enables
    deterministic double-click editing of numeric parameter labels. *)

val update_frame : t -> Prismel.Frame.t -> t * change list
(** Update from the frame's ordered events and logical time. This is the
    preferred sketch path and enables numeric-label double-click editing. *)

val scene : t -> Prismel.Scene.t
(** Describe the complete UI as composable scene data. Text fields and active
    numeric editors include pure text-input hit metadata used to summon mobile
    keyboards only when the editable control itself is pressed. *)

val add_label : t -> text:string -> unit
val add_button : t -> name:string -> label:string -> unit
val add_toggle : t -> name:string -> label:string -> value:bool -> unit
val add_slider :
  t -> name:string -> label:string -> min:float -> max:float -> value:float -> unit
val add_int_slider :
  t -> name:string -> label:string -> min:int -> max:int -> value:int -> unit
val add_text_field : t -> name:string -> label:string -> value:string -> unit
val draw : t -> unit
val handle_event : t -> Prismel.Event.t -> change list
val toggle_value : t -> string -> bool option
val set_toggle_value : t -> string -> bool -> t
val slider_value : t -> string -> float option
val set_slider_value : t -> string -> float -> t
val int_slider_value : t -> string -> int option
val set_int_slider_value : t -> string -> int -> t
val text_value : t -> string -> string option
val set_text_value : t -> string -> string -> t
val choice_value : t -> string -> string option
val set_choice_value : t -> string -> string -> t
val range_value : t -> string -> (float * float) option
val xy_value : t -> string -> (float * float) option
val accordion_expanded : t -> string -> bool option
val set_accordion_expanded : t -> string -> bool -> t

val with_position : x:int -> y:int -> t -> t

(** Resize a canvas without rebuilding its widgets, values, accordion state,
    or scroll position. Active pointer capture is cancelled because widget hit
    bounds changed. *)
val with_width : int -> t -> t

(** Set or remove the visible panel-height bound while retaining a clamped
    scroll offset. *)
val with_max_height : int option -> t -> t
(* Logical panel bounds after collapsed accordion rows are removed. *)
val bounds : t -> int * int * int * int

type canvas = t

module Camera_control : sig
  type t
  type render_request = {
    filename : string;
    factor : int;
  }

  val create : ?prefix:string -> unit -> t
  val append : t -> camera:Prismel.Easy_camera.t -> canvas -> canvas
  val update :
    ?control_area:(int * int * int * int) ->
    ?panel_visible:bool ->
    t ->
    ui:canvas ->
    camera:Prismel.Easy_camera.t ->
    Prismel.Frame.t ->
    t * canvas * Prismel.Easy_camera.t * change list * render_request list
  val scene : t -> canvas -> Prismel.Scene.t

  (** Show arbitrary labels and status overlays under the same [H] visibility
      state as the PXUI canvas. *)
  val overlay : t -> Prismel.Scene.t -> Prismel.Scene.t
  val ui_visible : t -> bool
  val save :
    ?background:Prismel.Color.t ->
    render_request ->
    frame:Prismel.Frame.t ->
    camera:Prismel.Easy_camera.t ->
    Prismel.Scene3.t ->
    (unit, string) result
  (** Append reusable FOV, clipping, distance, inertia, reset, render-factor,
      and PNG controls. [update] owns PXUI event handling, maps [C] to the
      camera accordion and [H] to all UI/overlay labels, reserves the resized
      non-UI viewport for camera gestures, and preserves middle/right-drag pan. *)
end

module Camera2_control : sig
  type t
  type render_request = {
    filename : string;
    factor : int;
  }

  val create : ?prefix:string -> unit -> t
  val append : t -> camera:Prismel.Easy_camera2.t -> canvas -> canvas
  val update :
    ?control_area:(int * int * int * int) ->
    ?viewport:(int * int * int * int) ->
    ?panel_visible:bool ->
    t ->
    ui:canvas ->
    camera:Prismel.Easy_camera2.t ->
    Prismel.Frame.t ->
    t * canvas * Prismel.Easy_camera2.t * change list * render_request list
  val scene : t -> canvas -> Prismel.Scene.t
  val overlay : t -> Prismel.Scene.t -> Prismel.Scene.t
  val ui_visible : t -> bool
  val save :
    ?background:Prismel.Color.t ->
    render_request ->
    frame:Prismel.Frame.t ->
    camera:Prismel.Easy_camera2.t ->
    Prismel.Scene.t ->
    (unit, string) result
  (** Append reusable center, zoom, rotation, inertia, reset, render-factor,
      and PNG controls. Shortcuts and visibility match [Camera_control]. *)
end

val encode : t -> string
val decode : t -> string -> (t, string) result
val save : t -> string -> (unit, string) result
val load : t -> string -> (t, string) result
(** Versioned persistence for toggle, slider, and text-field values. Unknown
    saved names are ignored; malformed or type-mismatched entries are errors. *)

module Private : sig
  module Store : sig
    type id
    type 'a t
    val create : ?capacity:int -> unit -> 'a t
    val capacity : 'a t -> int
    val length : 'a t -> int
    val add : 'a t -> 'a -> id
    val get : 'a t -> id -> 'a option
    val set : 'a t -> id -> 'a -> bool
    val remove : 'a t -> id -> bool
  end

  module Runtime : sig
    type id = Store.id
    type t
    type stats = {
      live : int;
      capacity : int;
      created : int;
      removed : int;
      mutations : int;
      structure_generation : int64;
      layout_generation : int64;
      paint_generation : int64;
      reconcile_visits : int;
      style_visits : int;
      layout_visits : int;
      prepaint_visits : int;
      text_visits : int;
      paint_visits : int;
      compose_visits : int;
      accessibility_visits : int;
      display_list_builds : int;
      display_list_reuses : int;
      display_list_evictions : int;
      display_list_entries : int;
      display_list_bytes : int;
    }
    val create : canvas -> t
    val reconcile : t -> canvas -> int
    val find : t -> string -> id option
    val valid : t -> id -> bool
    val length : t -> int
    val id_at : t -> int -> id option
    val parent : t -> id -> id option
    val set_focus : t -> id option -> bool
    val focus : t -> id option
    val set_active : t -> id option -> bool
    val active : t -> id option
    val dirty : t -> id -> int
    val clear_dirty : t -> unit
    val set_visible : t -> bool -> unit
    val visible : t -> bool
    val run_passes : t -> unit
    val pending : t -> int * int * int * int * int * int
    val layout_metrics : t -> int * int * int * int
    val bounds : t -> id ->
      (int * int * int * int * int * int * int * int) option
    val hit_test : t -> int * int -> id option
    val update : t -> Prismel.Event.t list -> change list
    val scene : ?density:int -> t -> canvas -> Prismel.Scene.t
    val stats : t -> stats
    val destroy : t -> unit
    val destroyed : t -> bool
  end
end

module Spec : sig
  type nonrec t = t
  val of_canvas : t -> t
end

module Runtime : module type of Private.Runtime
