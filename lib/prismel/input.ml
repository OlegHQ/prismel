(* Input module for handling keyboard and mouse input *)

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

(* Internal state for tracking input *)
module KeySet = Set.Make(struct
  type t = key
  let compare = compare
end)

module MouseButtonSet = Set.Make(struct
  type t = mouse_button
  let compare = compare
end)

(* Mutable state for input tracking *)
let pressed_keys = ref KeySet.empty
let current_mouse_pos = ref (0, 0)
let frame_mouse_delta = ref (0, 0)
let pressed_mouse_buttons = ref MouseButtonSet.empty

let reset ~mouse =
  pressed_keys := KeySet.empty;
  pressed_mouse_buttons := MouseButtonSet.empty;
  current_mouse_pos := mouse;
  frame_mouse_delta := (0, 0)

let begin_frame () =
  frame_mouse_delta := (0, 0)

(* Internal functions for updating state (called by event system) *)
let press_key key =
  pressed_keys := KeySet.add key !pressed_keys

let release_key key =
  pressed_keys := KeySet.remove key !pressed_keys

let update_mouse_pos x y =
  let current_x, current_y = !current_mouse_pos in
  let delta_x, delta_y = !frame_mouse_delta in
  frame_mouse_delta :=
    (delta_x + x - current_x, delta_y + y - current_y);
  current_mouse_pos := (x, y)

let press_mouse_button button =
  pressed_mouse_buttons := MouseButtonSet.add button !pressed_mouse_buttons

let release_mouse_button button =
  pressed_mouse_buttons := MouseButtonSet.remove button !pressed_mouse_buttons

(* Clear all input state (useful when window loses focus) *)
let clear_all_input () =
  pressed_keys := KeySet.empty;
  pressed_mouse_buttons := MouseButtonSet.empty

(* Public query functions *)

(* Check if a key is currently pressed *)
let is_key_down key =
  KeySet.mem key !pressed_keys

(* Check if a key is currently up (not pressed) *)
let is_key_up key =
  not (is_key_down key)

(* Get list of all currently pressed keys *)
let keys_down () =
  KeySet.elements !pressed_keys

(* Get current mouse position *)
let mouse_pos () =
  !current_mouse_pos

(* Get mouse movement delta since last frame *)
let mouse_delta () =
  !frame_mouse_delta

(* Check if a mouse button is currently pressed *)
let is_mouse_button_down button =
  MouseButtonSet.mem button !pressed_mouse_buttons

(* Get list of all currently pressed mouse buttons *)
let mouse_buttons_down () =
  MouseButtonSet.elements !pressed_mouse_buttons

(* Utility functions for key comparisons and pattern matching *)
let key_to_string = function
  | KeyChar c -> Printf.sprintf "KeyChar '%c'" c
  | ArrowUp -> "ArrowUp"
  | ArrowDown -> "ArrowDown"
  | ArrowLeft -> "ArrowLeft"
  | ArrowRight -> "ArrowRight"
  | Space -> "Space"
  | Enter -> "Enter"
  | Escape -> "Escape"
  | Backspace -> "Backspace"
  | Tab -> "Tab"
  | Shift -> "Shift"
  | Ctrl -> "Ctrl"
  | Alt -> "Alt"
  | Meta -> "Meta"
  | F1 -> "F1" | F2 -> "F2" | F3 -> "F3" | F4 -> "F4"
  | F5 -> "F5" | F6 -> "F6" | F7 -> "F7" | F8 -> "F8"
  | F9 -> "F9" | F10 -> "F10" | F11 -> "F11" | F12 -> "F12"
  | Home -> "Home"
  | End -> "End"
  | PageUp -> "PageUp"
  | PageDown -> "PageDown"
  | Insert -> "Insert"
  | Delete -> "Delete"
  | Unknown code -> Printf.sprintf "Unknown(%d)" code

let mouse_button_to_string = function
  | LeftButton -> "LeftButton"
  | RightButton -> "RightButton"
  | MiddleButton -> "MiddleButton"
  | MouseX1 -> "MouseX1"
  | MouseX2 -> "MouseX2"
