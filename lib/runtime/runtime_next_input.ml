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

type t = {
  max_events : int;
  max_file_bytes : int;
  events : event Queue.t;
  mutable pointer : float * float;
  mutable mouse_delta : float * float;
  mutable wheel_delta : float * float;
  mutable buttons : mouse_button list;
  mutable keys : string list;
  mutable pointer_captured : bool;
  mutable logical_width : int;
  mutable logical_height : int;
  mutable dropped_events : int;
}

let create ~max_events ~max_file_bytes ~logical_width ~logical_height =
  if max_events <= 0 then Error "max_events must be positive"
  else if max_file_bytes < 0 then Error "max_file_bytes must be non-negative"
  else if logical_width <= 0 || logical_height <= 0 then
    Error "logical dimensions must be positive"
  else
    Ok { max_events; max_file_bytes; events = Queue.create (); pointer = (0., 0.);
      mouse_delta = (0., 0.); wheel_delta = (0., 0.); buttons = []; keys = [];
      pointer_captured = false; logical_width; logical_height;
      dropped_events = 0 }

let add_unique value values =
  if List.mem value values then values else values @ [ value ]

let remove value values = List.filter (( <> ) value) values

let copy_event value event =
  match event with
  | File_dropped { name; contents = Some contents } ->
      if Bytes.length contents > value.max_file_bytes then
        Error "file drop exceeds max_file_bytes"
      else
        Ok (File_dropped { name;
             contents = Some (Bytes.copy contents) })
  | File_dropped { name; contents = None } ->
      Ok (File_dropped { name; contents = None })
  | event -> Ok event

let apply value = function
  | Pointer_moved (x, y) ->
      let old_x, old_y = value.pointer in
      let dx, dy = value.mouse_delta in
      value.pointer <- (x, y);
      value.mouse_delta <- (dx +. x -. old_x, dy +. y -. old_y)
  | Pointer_pressed (button, x, y) ->
      value.pointer <- (x, y);
      value.buttons <- add_unique button value.buttons;
      value.pointer_captured <- true
  | Pointer_released (button, x, y) ->
      value.pointer <- (x, y);
      value.buttons <- remove button value.buttons;
      value.pointer_captured <- value.buttons <> []
  | Pointer_cancelled button ->
      value.buttons <- remove button value.buttons;
      value.pointer_captured <- value.buttons <> []
  | Wheel (x, y) ->
      let old_x, old_y = value.wheel_delta in
      value.wheel_delta <- (old_x +. x, old_y +. y)
  | Key_pressed event -> value.keys <- add_unique event.key value.keys
  | Key_released event -> value.keys <- remove event.key value.keys
  | Focus_lost -> value.keys <- []
  | Resized (width, height) ->
      value.logical_width <- width;
      value.logical_height <- height
  | Text_input _ | Text_editing _ | File_dropped _ | Focus_gained
  | Visibility_changed _ | Quit -> ()

let push value event =
  match event with
  | Resized (width, height) when width <= 0 || height <= 0 ->
      Error "resize dimensions must be positive"
  | _ ->
      match copy_event value event with
      | Error _ as error -> error
      | Ok owned ->
          apply value owned;
          if Queue.length value.events = value.max_events then begin
            ignore (Queue.take value.events);
            value.dropped_events <- value.dropped_events + 1
          end;
          Queue.add owned value.events;
          Ok ()

let drain value =
  let events = List.of_seq (Queue.to_seq value.events) in
  Queue.clear value.events;
  events

let begin_frame value =
  value.mouse_delta <- (0., 0.);
  value.wheel_delta <- (0., 0.)

let snapshot value =
  { pointer = value.pointer; mouse_delta = value.mouse_delta;
    wheel_delta = value.wheel_delta; buttons = value.buttons; keys = value.keys;
    pointer_captured = value.pointer_captured;
    logical_width = value.logical_width; logical_height = value.logical_height;
    dropped_events = value.dropped_events }

let queued_count value = Queue.length value.events

let push_file_path value path =
  if path="" || String.contains path '\000' then Error"file-drop path is malformed"
  else
    try
      let input=open_in_bin path in
      Fun.protect~finally:(fun()->close_in_noerr input)(fun()->
        let length=in_channel_length input in
        if length>value.max_file_bytes then Error"file drop exceeds max_file_bytes"
        else
          let contents=Bytes.create length in
          really_input input contents 0 length;
          push value(File_dropped{name=Filename.basename path;contents=Some contents}))
    with Sys_error message->Error("file drop: "^message)
