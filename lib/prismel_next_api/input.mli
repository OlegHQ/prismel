type key = KeyChar of char | ArrowUp | ArrowDown | ArrowLeft | ArrowRight
  | Space | Enter | Escape | Backspace | Tab | Shift | Ctrl | Alt | Meta
  | F1 | F2 | F3 | F4 | F5 | F6 | F7 | F8 | F9 | F10 | F11 | F12
  | Home | End | PageUp | PageDown | Insert | Delete | Unknown of int
type mouse_button = LeftButton | RightButton | MiddleButton | MouseX1 | MouseX2
val reset : mouse:int*int -> unit
val begin_frame : unit -> unit
val press_key : key -> unit
val release_key : key -> unit
val update_mouse_pos : int -> int -> unit
val press_mouse_button : mouse_button -> unit
val release_mouse_button : mouse_button -> unit
val clear_all_input : unit -> unit
val is_key_down : key -> bool
val is_key_up : key -> bool
val keys_down : unit -> key list
val mouse_pos : unit -> int*int
val mouse_delta : unit -> int*int
val is_mouse_button_down : mouse_button -> bool
val mouse_buttons_down : unit -> mouse_button list
val key_to_string : key -> string
val mouse_button_to_string : mouse_button -> string
