(** Compact creative-coding UI toolkit for Prismel.

    A canvas owns widgets, lays them out vertically, draws them with Prismel,
    and translates Prismel mouse events into named UI changes. Rendering and
    hit testing share one logical-point layout. *)

type change =
  | Clicked of string
  | Toggled of string * bool
  | Slid of string * float
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
  unit ->
  t
(** Create a graphite/cyan panel using Prismel's installed system UI font by
    default. [font_size] is a logical point size; [font] overrides the default
    font resource. *)

val label : text:string -> t -> t
val button : name:string -> label:string -> t -> t
val toggle : name:string -> label:string -> value:bool -> t -> t
val slider :
  name:string -> label:string -> min:float -> max:float -> value:float -> t -> t
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

val update : t -> Prismel.Event.t list -> t * change list
(** Return an updated UI value and ordered changes without mutating the input.
    Buttons activate on release-inside. Sliders, ranges, and XY pads capture
    the pointer and emit continuous, clamped changes while dragging. *)

val scene : t -> Prismel.Scene.t
(** Describe the complete UI as composable scene data. Text fields include
    pure text-input hit metadata used to summon mobile keyboards only when the
    field itself is pressed. *)

val add_label : t -> text:string -> unit
val add_button : t -> name:string -> label:string -> unit
val add_toggle : t -> name:string -> label:string -> value:bool -> unit
val add_slider :
  t -> name:string -> label:string -> min:float -> max:float -> value:float -> unit
val add_text_field : t -> name:string -> label:string -> value:string -> unit
val draw : t -> unit
val handle_event : t -> Prismel.Event.t -> change list
val toggle_value : t -> string -> bool option
val slider_value : t -> string -> float option
val text_value : t -> string -> string option
val choice_value : t -> string -> string option
val range_value : t -> string -> (float * float) option
val xy_value : t -> string -> (float * float) option

val encode : t -> string
val decode : t -> string -> (t, string) result
val save : t -> string -> (unit, string) result
val load : t -> string -> (t, string) result
(** Versioned persistence for toggle, slider, and text-field values. Unknown
    saved names are ignored; malformed or type-mismatched entries are errors. *)
