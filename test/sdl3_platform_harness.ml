open Prismel

module Native = Sdl3.Event

let fail message = failwith ("SDL3 platform harness: " ^ message)

let point value = int_of_float value

let key ~scancode ~keycode =
  if keycode >= Char.code 'a' && keycode <= Char.code 'z' then
    Input.KeyChar (Char.chr keycode)
  else if keycode >= Char.code 'A' && keycode <= Char.code 'Z' then
    Input.KeyChar (Char.lowercase_ascii (Char.chr keycode))
  else if keycode >= Char.code '0' && keycode <= Char.code '9' then
    Input.KeyChar (Char.chr keycode)
  else
    match scancode with
    | 82 -> Input.ArrowUp
    | 81 -> Input.ArrowDown
    | 80 -> Input.ArrowLeft
    | 79 -> Input.ArrowRight
    | 44 -> Input.Space
    | 40 | 158 -> Input.Enter
    | 41 -> Input.Escape
    | 42 -> Input.Backspace
    | 43 -> Input.Tab
    | 225 | 229 -> Input.Shift
    | 224 | 228 -> Input.Ctrl
    | 226 | 230 -> Input.Alt
    | 227 | 231 -> Input.Meta
    | value when value >= 58 && value <= 69 ->
        [| Input.F1; Input.F2; Input.F3; Input.F4; Input.F5; Input.F6
         ; Input.F7; Input.F8; Input.F9; Input.F10; Input.F11; Input.F12
        |].(value - 58)
    | 74 -> Input.Home
    | 77 -> Input.End
    | 75 -> Input.PageUp
    | 78 -> Input.PageDown
    | 73 -> Input.Insert
    | 76 -> Input.Delete
    | _ -> Input.Unknown keycode

let button = function
  | 1 -> Some Input.LeftButton
  | 2 -> Some Input.MiddleButton
  | 3 -> Some Input.RightButton
  | 4 -> Some Input.MouseX1
  | 5 -> Some Input.MouseX2
  | _ -> None

let translate = function
  | Native.Quit _ -> Some Event.WindowClosed
  | Native.Key { down = true; repeat = false; scancode; keycode; _ } ->
      Some (Event.KeyPressed (key ~scancode ~keycode))
  | Native.Key { down = false; scancode; keycode; _ } ->
      Some (Event.KeyReleased (key ~scancode ~keycode))
  | Native.Key { down = true; repeat = true; _ } -> None
  | Native.Text_input { text; _ } -> Some (Event.TextInput text)
  | Native.Text_editing { text; start; length; _ } ->
      Some (Event.TextEditing { text; start; length })
  | Native.Mouse_motion { x; y; _ } ->
      Some (Event.MouseMoved (point x, point y))
  | Native.Mouse_button { button = native_button; down; x; y; _ } ->
      Option.map
        (fun button ->
          if down then Event.MousePressed (button, (point x, point y))
          else Event.MouseReleased (button, (point x, point y)))
        (button native_button)
  | Native.Mouse_wheel { integer_x; integer_y; _ } ->
      Some (Event.MouseScrolled (integer_x, integer_y))
  | Native.Touch { phase = Native.Cancelled; _ } ->
      Some (Event.PointerCancelled Input.LeftButton)
  | Native.Drop { change = Native.File path; _ } -> Some (Event.FileDropped path)
  | Native.Window { change = Native.Resized (width, height); _ }
    when width > 0 && height > 0 ->
      Some (Event.WindowResized (width, height))
  | Native.Window { change = Native.Focus_lost; _ } -> Some Event.WindowFocusLost
  | Native.Window { change = Native.Close_requested; _ } -> Some Event.WindowClosed
  | Native.Application _ | Native.Display _ | Native.Window _
  | Native.Keyboard_device _ | Native.Keymap_changed _
  | Native.Text_editing_candidates _ | Native.Screen_keyboard _
  | Native.Mouse_device _ | Native.Touch _ | Native.Pinch _
  | Native.Pen_proximity _ | Native.Pen_motion _ | Native.Pen_touch _
  | Native.Pen_button _ | Native.Pen_axis _ | Native.Gamepad_axis _
  | Native.Gamepad_button _ | Native.Gamepad_device _
  | Native.Gamepad_touchpad _ | Native.Gamepad_sensor _ | Native.Drop _
  | Native.Clipboard _ | Native.Audio_device _ | Native.Sensor _
  | Native.Unknown _ -> None

let apply_input = function
  | Event.KeyPressed key -> Input.press_key key
  | Event.KeyReleased key -> Input.release_key key
  | Event.MouseMoved (x, y) -> Input.update_mouse_pos x y
  | Event.MousePressed (button, (x, y)) ->
      Input.update_mouse_pos x y;
      Input.press_mouse_button button
  | Event.MouseReleased (button, (x, y)) ->
      Input.update_mouse_pos x y;
      Input.release_mouse_button button
  | Event.PointerCancelled button -> Input.release_mouse_button button
  | Event.WindowFocusLost -> Input.clear_all_input ()
  | Event.MouseScrolled _ | Event.TextInput _ | Event.TextEditing _
  | Event.FileDropped _ | Event.WindowResized _ | Event.WindowClosed -> ()

let timestamp_ns = 1L
let window_id = 7L

let events =
  [ Native.Key
      { timestamp_ns; window_id; which = 1L; scancode = 4
      ; keycode = Char.code 'a'; modifiers = 0; raw_scancode = 4; down = true
      ; repeat = false
      }
  ; Native.Key
      { timestamp_ns = 2L; window_id; which = 1L; scancode = 4
      ; keycode = Char.code 'a'; modifiers = 0; raw_scancode = 4; down = true
      ; repeat = true
      }
  ; Native.Text_input { timestamp_ns = 3L; window_id; text = "Žaba" }
  ; Native.Text_editing
      { timestamp_ns = 4L; window_id; text = "č"; start = 1; length = 2 }
  ; Native.Mouse_motion
      { timestamp_ns = 5L; window_id; which = 1L; buttons = 0L
      ; x = 10.; y = 10.; dx = 10.; dy = 10.
      }
  ; Native.Mouse_motion
      { timestamp_ns = 6L; window_id; which = 1L; buttons = 0L
      ; x = 13.; y = 17.; dx = 3.; dy = 7.
      }
  ; Native.Mouse_button
      { timestamp_ns = 7L; window_id; which = 1L; button = 1; down = true
      ; clicks = 1; x = 13.; y = 17.
      }
  ; Native.Mouse_wheel
      { timestamp_ns = 8L; window_id; which = 1L; x = 0.; y = 1.
      ; direction = Native.Normal; mouse_x = 13.; mouse_y = 17.
      ; integer_x = 0; integer_y = 1
      }
  ; Native.Drop
      { timestamp_ns = 9L; window_id; x = 13.; y = 17.; source = Some "test"
      ; change = Native.File "/tmp/žaba.png"
      }
  ; Native.Window
      { timestamp_ns = 10L; window_id; change = Native.Resized (80, 60) }
  ; Native.Touch
      { timestamp_ns = 11L; window_id; touch_id = 2L; finger_id = 3L
      ; phase = Native.Cancelled; x = 0.5; y = 0.5; dx = 0.; dy = 0.
      ; pressure = 0.
      }
  ; Native.Window
      { timestamp_ns = 12L; window_id; change = Native.Focus_lost }
  ; Native.Key
      { timestamp_ns = 13L; window_id; which = 1L; scancode = 4
      ; keycode = Char.code 'a'; modifiers = 0; raw_scancode = 4; down = false
      ; repeat = false
      }
  ]

let () =
  Input.reset ~mouse:(0, 0);
  Input.begin_frame ();
  let translated = List.filter_map translate events in
  List.iter apply_input translated;
  let expected =
    [ Event.KeyPressed (Input.KeyChar 'a')
    ; Event.TextInput "Žaba"
    ; Event.TextEditing { text = "č"; start = 1; length = 2 }
    ; Event.MouseMoved (10, 10)
    ; Event.MouseMoved (13, 17)
    ; Event.MousePressed (Input.LeftButton, (13, 17))
    ; Event.MouseScrolled (0, 1)
    ; Event.FileDropped "/tmp/žaba.png"
    ; Event.WindowResized (80, 60)
    ; Event.PointerCancelled Input.LeftButton
    ; Event.WindowFocusLost
    ; Event.KeyReleased (Input.KeyChar 'a')
    ]
  in
  if translated <> expected then
    fail
      (Printf.sprintf "translated trace changed:\n%s"
         (String.concat "\n" (List.map Event.event_to_string translated)));
  if Input.mouse_pos () <> (13, 17) || Input.mouse_delta () <> (13, 17) then
    fail "logical mouse position/delta changed";
  if Input.keys_down () <> [] || Input.mouse_buttons_down () <> [] then
    fail "focus loss/pointer cancellation left held input";
  Input.begin_frame ();
  if Input.mouse_delta () <> (0, 0) then
    fail "per-frame mouse delta did not reset";
  print_endline "SDL3 Runtime-shaped Prismel event/input trace passed"
