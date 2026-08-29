type mouse_button = Left | Middle | Right | X1 | X2
type modifier = Shift | Control | Alt | Meta | Num_lock | Caps_lock | Scroll_lock
type key_event = { key:string; modifiers:modifier list; repeat:bool }

type event =
  | Pointer_moved of float * float
  | Pointer_pressed of mouse_button * float * float
  | Pointer_released of mouse_button * float * float
  | Pointer_cancelled of mouse_button
  | Wheel of float * float
  | Key_pressed of key_event
  | Key_released of key_event
  | Text_input of string
  | Text_editing of { text : string; start : int; length : int }
  | Focus_lost
  | Focus_gained
  | Visibility_changed of bool
  | Quit
  | Resized of int * int
  | File_dropped of { name : string; contents : bytes option }

type snapshot = {
  pointer : float * float;
  mouse_delta : float * float;
  wheel_delta : float * float;
  buttons : mouse_button list;
  keys : string list;
  pointer_captured : bool;
  logical_width : int;
  logical_height : int;
  dropped_events : int;
}

type t

val create : max_events:int -> max_file_bytes:int ->
  logical_width:int -> logical_height:int -> (t, string) result
val push : t -> event -> (unit, string) result
val drain : t -> event list
val begin_frame : t -> unit
val set_extent : t -> logical_width:int -> logical_height:int -> (unit, string) result
val snapshot : t -> snapshot
val queued_count : t -> int
val push_file_path : t -> string -> (unit,string) result
