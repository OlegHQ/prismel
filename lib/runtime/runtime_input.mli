type mouse_button = Left | Middle | Right | X1 | X2

(** The binding's own variants: SDL's keycode is mapped once, in its stubs. A
    letter or digit is [Char] in lower case on any layout. *)
type key = Sdl3.Key.t =
  | Char of char
  | Arrow_up | Arrow_down | Arrow_left | Arrow_right
  | Space | Enter | Escape | Backspace | Tab
  | Shift | Control | Alt | Meta
  | F1 | F2 | F3 | F4 | F5 | F6 | F7 | F8 | F9 | F10 | F11 | F12
  | Home | End | Page_up | Page_down | Insert | Delete
  | Unknown of int

type scroll_phase = Sdl3.Event.scroll_phase =
  | Scroll_began | Scroll_changed | Scroll_ended | Scroll_momentum

type modifier = Sdl3.Key.modifier =
  | Shift_held | Control_held | Alt_held | Meta_held
  | Num_lock | Caps_lock | Scroll_lock

type key_event = { key : key; modifiers : modifier list; repeat : bool }

type event =
  | Pointer_moved of float * float
  | Pointer_pressed of mouse_button * float * float
  | Pointer_released of mouse_button * float * float
  | Pointer_cancelled of mouse_button
  | Wheel of float * float
  | Scroll of { x : float; y : float; phase : scroll_phase; seconds : float }
      (** A phased trackpad scroll in points ([Sdl3.Event.Scroll]). Its motion
          is also a [Wheel] of a tenth, which alone feeds [wheel_delta]. *)
  | Key_pressed of key_event
  | Key_released of key_event
  | Text_input of string
  | Text_editing of { text : string; start : int; length : int }
  | Focus_lost
  | Focus_gained
  | Visibility_changed of bool
      (** Shown, restored, hidden, minimized or covered. SDL never announces
          the end of occlusion: the caller reads the window. *)
  | Quit
  | Resized of int * int  (** logical points *)
  | Pixel_size_changed of int * int  (** drawable pixels *)
  | Pinch of float
      (** Trackpad pinch: the zoom factor since the last update, above 1 to
          zoom in. *)
  | File_dropped of string
  | File_dragged of float * float
      (** Files from the OS are over the window at this point. *)
  | File_drag_ended
  | Dialog_closed of { id : int; result : (string list, string) result }
      (** A native file dialog finished: the chosen paths ([] when the user
          cancelled) or the failure. *)

type snapshot = {
  pointer : float * float;
  mouse_delta : float * float;
  wheel_delta : float * float;
  buttons : mouse_button list;
  keys : key list;
  pointer_captured : bool;
  visible : bool;
  logical_width : int;
  logical_height : int;
  dropped_events : int;
}

type t

val create : max_events:int ->
  logical_width:int -> logical_height:int -> (t, string) result
val push : t -> event -> (unit, string) result
val drain : t -> event list
val begin_frame : t -> unit

val set_relative : t -> bool -> unit
val relative : t -> bool
(** In relative mode [mouse_delta] sums {!add_motion} deltas (SDL relative
    motion) instead of absolute pointer differences. *)

val add_motion : t -> dx:float -> dy:float -> unit
val set_extent : t -> logical_width:int -> logical_height:int -> (unit, string) result
val snapshot : t -> snapshot
val queued_count : t -> int
