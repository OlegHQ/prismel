type t = { mutable frame_files : string list; mutable dead : bool }

let create () =
  Input.reset ~mouse:(0, 0);
  { frame_files = []; dead = false }

let remove_file path =
  try Sys.remove path with Sys_error _ -> ()

let release_frame_files value =
  List.iter remove_file value.frame_files;
  value.frame_files <- []

let button = function
  | Runtime_next_input.Left -> Input.LeftButton
  | Middle -> MiddleButton
  | Right -> RightButton
  | X1 -> MouseX1
  | X2 -> MouseX2

let key value =
  match value with
  | value when String.length value = 1 ->
      Input.KeyChar (Char.lowercase_ascii value.[0])
  | "ArrowUp" -> ArrowUp
  | "ArrowDown" -> ArrowDown
  | "ArrowLeft" -> ArrowLeft
  | "ArrowRight" -> ArrowRight
  | "Space" | " " -> Space
  | "Enter" -> Enter
  | "Escape" -> Escape
  | "Backspace" -> Backspace
  | "Tab" -> Tab
  | "Shift" -> Shift
  | "Control" -> Ctrl
  | "Alt" -> Alt
  | "Meta" -> Meta
  | "F1" -> F1 | "F2" -> F2 | "F3" -> F3 | "F4" -> F4
  | "F5" -> F5 | "F6" -> F6 | "F7" -> F7 | "F8" -> F8
  | "F9" -> F9 | "F10" -> F10 | "F11" -> F11 | "F12" -> F12
  | "Home" -> Home
  | "End" -> End
  | "PageUp" -> PageUp
  | "PageDown" -> PageDown
  | "Insert" -> Insert
  | "Delete" -> Delete
  | numeric ->
      begin
        match int_of_string_opt numeric with
        | Some code when code >= Char.code 'A' && code <= Char.code 'Z' ->
            Input.KeyChar
              (Char.lowercase_ascii (Char.chr code))
        | Some code when code >= Char.code 'a' && code <= Char.code 'z' ->
            Input.KeyChar (Char.chr code)
        | Some code -> Unknown code
        | None -> Unknown 0
      end

let integer value = int_of_float value

let materialize value name contents =
  let suffix =
    let candidate = Filename.extension name in
    if String.length candidate > 0 && String.length candidate <= 16 then
      candidate
    else ".upload"
  in
  let path = Filename.temp_file "prismel-next-drop-" suffix in
  let channel = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out_noerr channel)
    (fun () -> output_bytes channel contents);
  value.frame_files <- path :: value.frame_files;
  path

let convert value event =
  match event with
  | Runtime_next_input.Pointer_moved (x, y) ->
      let position = integer x, integer y in
      Input.update_mouse_pos (fst position) (snd position);
      Some(Event.MouseMoved position)
  | Pointer_pressed (raw_button, x, y) ->
      let input_button = button raw_button in
      let position = integer x, integer y in
      Input.update_mouse_pos (fst position) (snd position);
      Input.press_mouse_button input_button;
      Some(MousePressed (input_button, position))
  | Pointer_released (raw_button, x, y) ->
      let input_button = button raw_button in
      let position = integer x, integer y in
      Input.update_mouse_pos (fst position) (snd position);
      Input.release_mouse_button input_button;
      Some(MouseReleased (input_button, position))
  | Pointer_cancelled raw_button ->
      let input_button = button raw_button in
      Input.release_mouse_button input_button;
      Some(PointerCancelled input_button)
  | Wheel (x, y) -> Some(MouseScrolled (integer x, integer y))
  | Key_pressed raw_key ->
      let input_key = key raw_key.key in
      Input.press_key input_key;
      Some(KeyPressed input_key)
  | Key_released raw_key ->
      let input_key = key raw_key.key in
      Input.release_key input_key;
      Some(KeyReleased input_key)
  | Text_input text -> Some(TextInput text)
  | Text_editing { text; start; length } ->
      Some(TextEditing { text; start; length })
  | Focus_lost ->
      Input.clear_all_input ();
      Some WindowFocusLost
  | Focus_gained | Visibility_changed _ -> None
  | Quit -> Some WindowClosed
  | Resized (width, height) -> Some(WindowResized (width, height))
  | File_dropped { name; contents = None } -> Some(FileDropped name)
  | File_dropped { name; contents = Some contents } ->
      Some(FileDropped (materialize value name contents))

let frame value ~facts ~events ~drawable_width ~drawable_height ~time ~dt ~fps
    ~count =
  if value.dead then invalid_arg "Prismel runtime-next input adapter is destroyed";
  if drawable_width <= 0 || drawable_height <= 0 then
    invalid_arg "Prismel runtime-next drawable dimensions must be positive";
  release_frame_files value;
  Input.begin_frame ();
  let events = List.filter_map (convert value) events in
  let width = facts.Runtime_next_input.logical_width
  and height = facts.logical_height in
  {
    Frame.width;
    height;
    size = (width, height);
    drawable_width;
    drawable_height;
    drawable_size = (drawable_width, drawable_height);
    pixel_scale =
      (float drawable_width /. float width, float drawable_height /. float height);
    time;
    dt;
    fps;
    count;
    mouse = Input.mouse_pos ();
    mouse_delta = Input.mouse_delta ();
    keys = Input.keys_down ();
    mouse_buttons = Input.mouse_buttons_down ();
    events;
  }

let destroy value =
  if not value.dead then begin
    value.dead <- true;
    release_frame_files value;
    Input.clear_all_input ()
  end

let test () =
  let facts width height =
    { Runtime_next_input.pointer = (9., 14.); mouse_delta = (9., 14.);
      wheel_delta = (0., 0.); buttons = []; keys = [];
      pointer_captured = false; logical_width = width;
      logical_height = height; dropped_events = 0 }
  in
  let fixture =
    [ Runtime_next_input.Pointer_moved (7., 11.);
      Pointer_pressed (Left, 7., 11.); Pointer_moved (9., 14.);
      Pointer_released (Left, 9., 14.); Wheel (1., -2.);
      Key_pressed {key="a";modifiers=[];repeat=false};
      Key_released {key="a";modifiers=[];repeat=false}; Text_input "a";
      Text_editing { text = "ab"; start = 1; length = 1 };
      Resized (20, 10); Focus_lost ]
  in
  let expected =
    [ Event.MouseMoved (7, 11); MousePressed (Input.LeftButton, (7, 11));
      MouseMoved (9, 14); MouseReleased (LeftButton, (9, 14));
      MouseScrolled (1, -2); KeyPressed (KeyChar 'a');
      KeyReleased (KeyChar 'a'); TextInput "a";
      TextEditing { text = "ab"; start = 1; length = 1 };
      WindowResized (20, 10); WindowFocusLost ]
  in
  let adapter = create () in
  let result = frame adapter ~facts:(facts 20 10)
      ~events:(List.concat [ fixture; fixture; fixture ])
      ~drawable_width:40 ~drawable_height:30 ~time:1. ~dt:(1. /. 60.)
      ~fps:60. ~count:1 in
  if result.events <> List.concat [ expected; expected; expected ]
     || List.length result.events <> 33 then
    failwith "runtime-next/public legacy frozen trace differs";
  if result.mouse <> (9, 14) || result.mouse_delta <> (9, 14)
     || result.size <> (20, 10) || result.drawable_size <> (40, 30)
     || result.pixel_scale <> (2., 3.) then
    failwith "runtime-next public Frame/Input facts differ";
  let empty = frame adapter ~facts:(facts 20 10) ~events:[]
      ~drawable_width:40 ~drawable_height:30 ~time:2. ~dt:1. ~fps:1.
      ~count:2 in
  if empty.events <> [] || empty.mouse_delta <> (0, 0) then
    failwith "headless no-input/frame reset differs";
  let cancellation = frame adapter ~facts:(facts 20 10)
      ~events:[ Pointer_pressed (Left, 1., 1.); Focus_lost;
                Pointer_cancelled Left ]
      ~drawable_width:20 ~drawable_height:10 ~time:3. ~dt:1. ~fps:1.
      ~count:3 in
  if cancellation.events <>
       [ Event.MousePressed (LeftButton, (1, 1)); WindowFocusLost;
         PointerCancelled LeftButton ]
     || cancellation.mouse_buttons <> [] then
    failwith "focus/cancellation public semantics differ";
  let dropped = frame adapter ~facts:(facts 20 10)
      ~events:[ File_dropped { name = "asset.bin";
                  contents = Some (Bytes.of_string "bounded") } ]
      ~drawable_width:20 ~drawable_height:10 ~time:4. ~dt:1. ~fps:1.
      ~count:4 in
  let path = match dropped.events with [ Event.FileDropped path ] -> path
    | _ -> failwith "file drop event missing" in
  if not (Sys.file_exists path) then failwith "file drop expired within frame";
  ignore (frame adapter ~facts:(facts 20 10) ~events:[]
      ~drawable_width:20 ~drawable_height:10 ~time:5. ~dt:1. ~fps:1.
      ~count:5);
  if Sys.file_exists path then failwith "file drop outlived its bounded frame";
  destroy adapter;
  print_endline
    "Prismel runtime-next compatibility: trace33, Frame/Input, bounded drop passed"

let () =
  match Sys.getenv_opt "PRISMEL_TEST_RUNTIME_NEXT_INPUT_COMPAT" with
  | Some "1" -> test ()
  | _ -> ()
