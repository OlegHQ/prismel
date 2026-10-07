(** Renderer-independent, immutable facts about one logical frame. *)
type event =
  | Key_pressed of string | Key_released of string
  | Pointer_moved of float * float
  | Pointer_pressed of string * (float * float)
  | Pointer_released of string * (float * float)
  | Pointer_cancelled of string
  | Scrolled of float * float
  | Text_input of string
  | Text_editing of { text : string; start : int; length : int }
  | File_dropped of string | File_drag_moved of float * float | File_drag_ended
  | Pinched of float
  | File_dialog of { id : int; result : (string list, string) result }
  | Resized of int * int | Focus_lost | Closed
  | Trackpad_scrolled of { delta : float * float; phase : string; time : float }

type t = {
  t : float; dt : float; frame : int; size : int * int;
  pointer : float * float; buttons : string list; keys : string list;
  events : event list;
}

val at_time : float -> t
(** A deterministic frame with the given time and other fields zero or empty.
    Hosts supply the full record; this constructor is for time-only tools. *)

val validate : t -> (unit, string) result

val key : t -> string
(** Exact identity of every frame field, including ordered events. *)

val equal : t -> t -> bool
(** Equality includes the exact bits of floating-point facts. *)
