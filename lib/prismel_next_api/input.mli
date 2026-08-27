(* Input module interface for handling keyboard and mouse input *)

(* Key type representing all keyboard keys *)
type key =
  | KeyChar of char  (* for 'a'-'z', '0'-'9', etc. *)
  | ArrowUp | ArrowDown | ArrowLeft | ArrowRight
  | Space | Enter | Escape | Backspace | Tab
  | Shift | Ctrl | Alt | Meta
  | F1 | F2 | F3 | F4 | F5 | F6 | F7 | F8 | F9 | F10 | F11 | F12
  | Home | End | PageUp | PageDown
  | Insert | Delete
  | Unknown of int

(* Mouse button type *)
type mouse_button =
  | LeftButton
  | RightButton
  | MiddleButton
  | MouseX1
  | MouseX2

(* Internal functions for updating state (called by event system) *)
val reset : mouse:int * int -> unit
val begin_frame : unit -> unit
val press_key : key -> unit
val release_key : key -> unit
val update_mouse_pos : int -> int -> unit
val press_mouse_button : mouse_button -> unit
val release_mouse_button : mouse_button -> unit
val clear_all_input : unit -> unit

(* Public query functions *)

(* Check if a key is currently pressed *)
val is_key_down : key -> bool

(* Check if a key is currently up (not pressed) *)
val is_key_up : key -> bool

(* Get list of all currently pressed keys *)
val keys_down : unit -> key list

(* Get current mouse position *)
val mouse_pos : unit -> (int * int)

(* Get mouse movement delta since last frame *)
val mouse_delta : unit -> (int * int)

(* Check if a mouse button is currently pressed *)
val is_mouse_button_down : mouse_button -> bool

(* Get list of all currently pressed mouse buttons *)
val mouse_buttons_down : unit -> mouse_button list

(* Utility functions for debugging and display *)
val key_to_string : key -> string
val mouse_button_to_string : mouse_button -> string 

