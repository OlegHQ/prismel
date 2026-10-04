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
