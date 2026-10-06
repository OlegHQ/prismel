type mouse_button = Left | Middle | Right | X1 | X2

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
  | Key_pressed of key_event
  | Key_released of key_event
  | Text_input of string
  | Text_editing of { text : string; start : int; length : int }
  | Focus_lost
  | Focus_gained
  | Visibility_changed of bool
  | Quit
  | Resized of int * int
  | Pixel_size_changed of int * int
  | Pinch of float
  | File_dropped of string
  | File_dragged of float * float
  | File_drag_ended
  | Dialog_closed of { id : int; result : (string list, string) result }

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

(* All-float records store their fields unboxed, so per-event updates below
   assign in place instead of allocating tuples and boxed floats. *)
type pair = { mutable px : float; mutable py : float }

type t = {
  max_events : int;
  events : event Queue.t;
  pointer : pair;
  mouse_delta : pair;
  wheel_delta : pair;
  mutable buttons : mouse_button list;
  mutable keys : key list;
  mutable pointer_captured : bool;
  mutable visible : bool;
  mutable logical_width : int;
  mutable logical_height : int;
  mutable dropped_events : int;
  (* Relative (captured) pointer mode: motion deltas come from the device's
     relative motion, since absolute positions stop at the window edge. *)
  mutable relative : bool;
}

let create ~max_events ~logical_width ~logical_height =
  if max_events <= 0 then Error "max_events must be positive"
  else if logical_width <= 0 || logical_height <= 0 then Error "logical dimensions must be positive"
  else
    Ok
      {
        max_events;
        events = Queue.create ();
        pointer = { px = 0.; py = 0. };
        mouse_delta = { px = 0.; py = 0. };
        wheel_delta = { px = 0.; py = 0. };
        buttons = [];
        keys = [];
        pointer_captured = false;
        visible = true;
        logical_width;
        logical_height;
        dropped_events = 0;
        relative = false;
      }

let add_unique value values = if List.mem value values then values else values @ [ value ]
let remove value values = List.filter (( <> ) value) values

let apply value = function
  | Pointer_moved (x, y) ->
      let pointer = value.pointer and delta = value.mouse_delta in
      if not value.relative then begin
        delta.px <- delta.px +. x -. pointer.px;
        delta.py <- delta.py +. y -. pointer.py
      end;
      pointer.px <- x;
      pointer.py <- y
  | Pointer_pressed (button, x, y) ->
      value.pointer.px <- x;
      value.pointer.py <- y;
      value.buttons <- add_unique button value.buttons;
      value.pointer_captured <- true
  | Pointer_released (button, x, y) ->
      value.pointer.px <- x;
      value.pointer.py <- y;
      value.buttons <- remove button value.buttons;
      value.pointer_captured <- value.buttons <> []
  | Pointer_cancelled button ->
      value.buttons <- remove button value.buttons;
      value.pointer_captured <- value.buttons <> []
  | Wheel (x, y) ->
      value.wheel_delta.px <- value.wheel_delta.px +. x;
      value.wheel_delta.py <- value.wheel_delta.py +. y
  | Key_pressed event -> value.keys <- add_unique event.key value.keys
  | Key_released event -> value.keys <- remove event.key value.keys
  | Focus_lost ->
      (* The matching releases go to another window, so held input and
         capture end here. *)
      value.keys <- [];
      value.buttons <- [];
      value.pointer_captured <- false
  | Resized (width, height) ->
      value.logical_width <- width;
      value.logical_height <- height
  | Visibility_changed visible -> value.visible <- visible
  | Text_input _ | Text_editing _ | File_dropped _ | File_dragged _ | File_drag_ended
  | Pixel_size_changed _ | Pinch _ | Scroll _ | Focus_gained | Quit | Dialog_closed _ -> ()

let push value event =
  match event with
  | File_dropped path when path = "" || String.contains path '\000' ->
      Error "file-drop path is malformed"
  | (Resized (width, height) | Pixel_size_changed (width, height))
    when width <= 0 || height <= 0 ->
      Error "resize dimensions must be positive"
  | Pinch scale when not (Float.is_finite scale) || scale <= 0. ->
      Error "pinch scale must be finite and positive"
  | Scroll { x; y; seconds; _ }
    when not (Float.is_finite x && Float.is_finite y && Float.is_finite seconds) ->
      Error "scroll gesture must be finite"
  | _ ->
      apply value event;
      if Queue.length value.events = value.max_events then begin
        ignore (Queue.take value.events);
        value.dropped_events <- value.dropped_events + 1
      end;
      Queue.add event value.events;
      Ok ()

let drain value =
  let events = List.rev (Queue.fold (fun acc event -> event :: acc) [] value.events) in
  Queue.clear value.events;
  events

let set_relative value relative = value.relative <- relative
let relative value = value.relative

let add_motion value ~dx ~dy =
  if value.relative then begin
    value.mouse_delta.px <- value.mouse_delta.px +. dx;
    value.mouse_delta.py <- value.mouse_delta.py +. dy
  end

let begin_frame value =
  value.mouse_delta.px <- 0.;
  value.mouse_delta.py <- 0.;
  value.wheel_delta.px <- 0.;
  value.wheel_delta.py <- 0.

let set_extent value ~logical_width ~logical_height =
  if logical_width <= 0 || logical_height <= 0 then Error "logical dimensions must be positive"
  else begin
    value.logical_width <- logical_width;
    value.logical_height <- logical_height;
    Ok ()
  end

let snapshot value =
  {
    pointer = (value.pointer.px, value.pointer.py);
    mouse_delta = (value.mouse_delta.px, value.mouse_delta.py);
    wheel_delta = (value.wheel_delta.px, value.wheel_delta.py);
    buttons = value.buttons;
    keys = value.keys;
    pointer_captured = value.pointer_captured;
    visible = value.visible;
    logical_width = value.logical_width;
    logical_height = value.logical_height;
    dropped_events = value.dropped_events;
  }

let queued_count value = Queue.length value.events
