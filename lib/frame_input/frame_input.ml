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
  | Dialog_opened of int
  | Resized of int * int | Focus_lost | Closed
  | Trackpad_scrolled of { delta : float * float; phase : string; time : float }

type t = {
  t : float; dt : float; frame : int; tick : int; size : int * int;
  pointer : float * float; buttons : string list; keys : string list;
  events : event list;
}
let at_time t = {t; dt = 0.; frame = 0; tick = 0; size = 0, 0; pointer = 0., 0.;
  buttons = []; keys = []; events = []}
let validate v =
  let x, y = v.pointer and w, h = v.size in
  let pair (x, y) = Float.is_finite x && Float.is_finite y in
  let event = function
    | Pointer_moved (x, y) | Scrolled (x, y) | File_drag_moved (x, y) -> pair (x, y)
    | Pointer_pressed (_, p) | Pointer_released (_, p) -> pair p
    | Pinched f -> Float.is_finite f
    | Trackpad_scrolled {delta; time; _} -> pair delta && Float.is_finite time
    | Text_editing {start; length; _} -> start >= 0 && length >= 0
    | Resized (w, h) -> w >= 0 && h >= 0
    | _ -> true in
  if not (List.for_all Float.is_finite [v.t; v.dt; x; y]) || not (List.for_all event v.events) then
    Error "Frame facts must be finite; event dimensions and text ranges must be non-negative."
  else if v.dt < 0. || v.frame < 0 || v.tick < 0 || w < 0 || h < 0 then
    Error "Frame step, index and dimensions must be non-negative."
  else Ok ()
let key v = Marshal.to_string v []
let equal a b =
  let bits x y = Int64.bits_of_float x = Int64.bits_of_float y in
  a == b || (bits a.t b.t && bits a.dt b.dt && a.frame = b.frame && a.tick = b.tick && a.size = b.size
    && bits (fst a.pointer) (fst b.pointer) && bits (snd a.pointer) (snd b.pointer)
    && a.buttons = b.buttons && a.keys = b.keys
    && (a.events == b.events || (a.events = b.events
      && Marshal.to_string a.events [] = Marshal.to_string b.events [])))
