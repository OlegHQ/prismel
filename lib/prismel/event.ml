(* Event module for handling input events *)

(* Event type representing all framework events *)
type t =
  | KeyPressed of Input.key
  | KeyReleased of Input.key
  | MouseMoved of (int * int)                                (* new mouse position *)
  | MousePressed of Input.mouse_button * (int * int)        (* button and position *)
  | MouseReleased of Input.mouse_button * (int * int)       (* button and position *)
  | PointerCancelled of Input.mouse_button                  (* browser/OS cancelled pointer *)
  | MouseScrolled of (int * int)                             (* scroll delta x,y *)
  | TextInput of string
  | TextEditing of { text : string; start : int; length : int }
  | FileDropped of string
  | WindowResized of (int * int)                             (* new width and height *)
  | WindowFocusLost
  | WindowClosed                                             (* user attempted to close *)

(* SDL to Input.key translation *)
let sdl_key_to_input_key sym =
  let open Tsdl.Sdl in
  match sym with
  (* a-z *)
  | k when k >= K.a && k <= K.z ->
    Input.KeyChar (char_of_int (int_of_char 'a' + (k - K.a)))

(* keypad 0-9 *)
| k when k >= K.kp_0 && k <= K.kp_9 ->
    Input.KeyChar (char_of_int (int_of_char '0' + (k - K.kp_0)))

(* top-row 0-9 *)
| k when k >= K.k0 && k <= K.k9 ->
    Input.KeyChar (char_of_int (int_of_char '0' + (k - K.k0)))
  
  (* Arrow keys *)
  | k when k = K.up -> Input.ArrowUp
  | k when k = K.down -> Input.ArrowDown
  | k when k = K.left -> Input.ArrowLeft
  | k when k = K.right -> Input.ArrowRight
  
  (* Special keys *)
  | k when k = K.space -> Input.Space
  | k when k = K.return || k = K.return2 -> Input.Enter
  | k when k = K.escape -> Input.Escape
  | k when k = K.backspace -> Input.Backspace
  | k when k = K.tab -> Input.Tab
  
  (* Modifier keys *)
  | k when k = K.lshift || k = K.rshift -> Input.Shift
  | k when k = K.lctrl || k = K.rctrl -> Input.Ctrl
  | k when k = K.lalt || k = K.ralt -> Input.Alt
  | k when k = K.lgui || k = K.rgui -> Input.Meta
  
  (* Function keys *)
  | k when k = K.f1 -> Input.F1
  | k when k = K.f2 -> Input.F2
  | k when k = K.f3 -> Input.F3
  | k when k = K.f4 -> Input.F4
  | k when k = K.f5 -> Input.F5
  | k when k = K.f6 -> Input.F6
  | k when k = K.f7 -> Input.F7
  | k when k = K.f8 -> Input.F8
  | k when k = K.f9 -> Input.F9
  | k when k = K.f10 -> Input.F10
  | k when k = K.f11 -> Input.F11
  | k when k = K.f12 -> Input.F12
  
  (* Navigation keys *)
  | k when k = K.home -> Input.Home
  | k when k = K.kend -> Input.End
  | k when k = K.pageup -> Input.PageUp
  | k when k = K.pagedown -> Input.PageDown
  | k when k = K.insert -> Input.Insert
  | k when k = K.delete -> Input.Delete
  
  (* Unknown key *)
  | k -> Input.Unknown ( k)

(* SDL to Input.mouse_button translation *)
let sdl_button_to_input_button button =
  match button with
  | 1 -> Some Input.LeftButton      (* SDL_BUTTON_LEFT *)
  | 2 -> Some Input.MiddleButton    (* SDL_BUTTON_MIDDLE *)
  | 3 -> Some Input.RightButton     (* SDL_BUTTON_RIGHT *)
  | 4 -> Some Input.MouseX1         (* SDL_BUTTON_X1 *)
  | 5 -> Some Input.MouseX2         (* SDL_BUTTON_X2 *)
  | _ -> None

let web_button_to_input_button = function
  | Runtime.Left -> Input.LeftButton
  | Middle -> Input.MiddleButton
  | Right -> Input.RightButton
  | X1 -> Input.MouseX1
  | X2 -> Input.MouseX2

let web_key_to_input_key value =
  match value with
  | value when String.length value = 1 ->
      Input.KeyChar (Char.lowercase_ascii value.[0])
  | "ArrowUp" -> Input.ArrowUp
  | "ArrowDown" -> Input.ArrowDown
  | "ArrowLeft" -> Input.ArrowLeft
  | "ArrowRight" -> Input.ArrowRight
  | "Space" | " " -> Input.Space
  | "Enter" -> Input.Enter
  | "Escape" -> Input.Escape
  | "Backspace" -> Input.Backspace
  | "Tab" -> Input.Tab
  | "Shift" -> Input.Shift
  | "Control" -> Input.Ctrl
  | "Alt" -> Input.Alt
  | "Meta" -> Input.Meta
  | "F1" -> Input.F1 | "F2" -> Input.F2 | "F3" -> Input.F3
  | "F4" -> Input.F4 | "F5" -> Input.F5 | "F6" -> Input.F6
  | "F7" -> Input.F7 | "F8" -> Input.F8 | "F9" -> Input.F9
  | "F10" -> Input.F10 | "F11" -> Input.F11 | "F12" -> Input.F12
  | "Home" -> Input.Home
  | "End" -> Input.End
  | "PageUp" -> Input.PageUp
  | "PageDown" -> Input.PageDown
  | "Insert" -> Input.Insert
  | "Delete" -> Input.Delete
  | _ -> Input.Unknown 0

let web_event_to_event = function
  | Runtime.Pointer_moved (x, y) -> Some (MouseMoved (x, y))
  | Pointer_pressed (button, x, y) ->
      Some (MousePressed (web_button_to_input_button button, (x, y)))
  | Pointer_released (button, x, y) ->
      Some (MouseReleased (web_button_to_input_button button, (x, y)))
  | Pointer_cancelled button ->
      Some (PointerCancelled (web_button_to_input_button button))
  | Wheel (x, y) -> Some (MouseScrolled (x, y))
  | Key_pressed key -> Some (KeyPressed (web_key_to_input_key key))
  | Key_released key -> Some (KeyReleased (web_key_to_input_key key))
  | Text_input text -> Some (TextInput text)
  | Text_editing { text; start; length } ->
      Some (TextEditing { text; start; length })
  | Resized (width, height)
    when width > 0 && height > 0 && width <= 8_192 && height <= 8_192
         && width * height <= 33_554_432 ->
      Some (WindowResized (width, height))
  | Resized _ -> None
  | Focus_lost -> Some WindowFocusLost
  | File_dropped path -> Some (FileDropped path)

(* Convert an SDL event to our Event.t *)
let sdl_event_to_event sdl_event =
  let open Tsdl.Sdl in
  match Event.enum (Event.get sdl_event Event.typ) with
  | `Key_down ->
      let repeat = Event.get sdl_event Event.keyboard_repeat in
      if repeat = 0 then
        let sym = Event.get sdl_event Event.keyboard_keycode in
        Some (KeyPressed (sdl_key_to_input_key sym))
      else
        None

  | `Key_up ->
      let sym = Event.get sdl_event Event.keyboard_keycode in
      Some (KeyReleased (sdl_key_to_input_key sym))

  | `Mouse_motion ->
      let x = Event.get sdl_event Event.mouse_motion_x in
      let y = Event.get sdl_event Event.mouse_motion_y in
      Some (MouseMoved (x, y))

  | `Mouse_button_down ->
      let button = Event.get sdl_event Event.mouse_button_button in
      let x = Event.get sdl_event Event.mouse_button_x in
      let y = Event.get sdl_event Event.mouse_button_y in
      Option.map
        (fun button -> MousePressed (button, (x, y)))
        (sdl_button_to_input_button button)

  | `Mouse_button_up ->
      let button = Event.get sdl_event Event.mouse_button_button in
      let x = Event.get sdl_event Event.mouse_button_x in
      let y = Event.get sdl_event Event.mouse_button_y in
      Option.map
        (fun button -> MouseReleased (button, (x, y)))
        (sdl_button_to_input_button button)

  | `Mouse_wheel ->
      let x = Event.get sdl_event Event.mouse_wheel_x in
      let y = Event.get sdl_event Event.mouse_wheel_y in
      Some (MouseScrolled (x, y))

  | `Text_input ->
      Some (TextInput (Event.get sdl_event Event.text_input_text))

  | `Text_editing ->
      Some (TextEditing {
        text = Event.get sdl_event Event.text_editing_text;
        start = Event.get sdl_event Event.text_editing_start;
        length = Event.get sdl_event Event.text_editing_length;
      })

  | `Drop_file ->
      let path = Event.drop_file_file sdl_event in
      Event.drop_file_free sdl_event;
      Option.map (fun path -> FileDropped path) path

  | `Window_event ->
      (match Event.window_event_enum (Event.get sdl_event Event.window_event_id) with
       | `Size_changed ->
           if Backend.is_web () then None
           else
             let w = Event.get sdl_event Event.window_data1 in
             let h = Event.get sdl_event Event.window_data2 in
             Some (WindowResized (Int32.to_int w, Int32.to_int h))
       | `Resized -> None
       | `Focus_lost -> Some WindowFocusLost
       | `Close -> Some WindowClosed
       | _ -> None)

  | `Quit -> Some WindowClosed
  | _ -> None

(* Update Input module state based on event *)
let update_input_state event =
  match event with
  | KeyPressed key -> Input.press_key key
  | KeyReleased key -> Input.release_key key
  | MouseMoved (x, y) -> Input.update_mouse_pos x y
  | MousePressed (button, (x, y)) -> 
      Input.update_mouse_pos x y;
      Input.press_mouse_button button
  | MouseReleased (button, (x, y)) -> 
      Input.update_mouse_pos x y;
      Input.release_mouse_button button
  | PointerCancelled button -> Input.release_mouse_button button
  | MouseScrolled _ -> () (* No persistent state for scroll *)
  | TextInput _ | TextEditing _ | FileDropped _ -> ()
  | WindowResized (width, height) ->
      if Backend.is_web () then Window.set_web_size width height
      else Window.update_dimensions width height
  | WindowFocusLost -> Input.clear_all_input ()
  | WindowClosed -> () (* Handled by main loop *)

(* Poll all pending events from SDL and convert to our events *)
let poll_events () =
  let open Tsdl.Sdl in
  let sdl_event = Event.create () in
  let rec poll_loop acc =
    match poll_event (Some sdl_event) with
    | false -> List.rev acc  (* No more events *)
    | true ->
        (match sdl_event_to_event sdl_event with
         | Some event ->
             update_input_state event;
             poll_loop (event :: acc)
         | None ->
             poll_loop acc)
  in
  let sdl_events = poll_loop [] in
  let web_events =
    Backend.drain_web_events () |> List.filter_map web_event_to_event
  in
  let events = sdl_events @ web_events in
  List.iter update_input_state web_events;
  events

(* Process events through user's event handler *)
let process_events events state on_event_opt =
  match on_event_opt with
  | Some on_event ->
      List.fold_left on_event state events
  | None ->
      state  (* No event handler, just return state unchanged *)

(* Main event processing function *)
let handle_events state on_event_opt =
  let events = poll_events () in
  let new_state = process_events events state on_event_opt in
  (new_state, events)

(* Utility function to convert event to string for debugging *)
let event_to_string = function
  | KeyPressed key -> "KeyPressed(" ^ Input.key_to_string key ^ ")"
  | KeyReleased key -> "KeyReleased(" ^ Input.key_to_string key ^ ")"
  | MouseMoved (x, y) -> Printf.sprintf "MouseMoved(%d, %d)" x y
  | MousePressed (button, (x, y)) -> 
      Printf.sprintf "MousePressed(%s, (%d, %d))" (Input.mouse_button_to_string button) x y
  | MouseReleased (button, (x, y)) -> 
      Printf.sprintf "MouseReleased(%s, (%d, %d))" (Input.mouse_button_to_string button) x y
  | PointerCancelled button ->
      Printf.sprintf "PointerCancelled(%s)"
        (Input.mouse_button_to_string button)
  | MouseScrolled (dx, dy) -> Printf.sprintf "MouseScrolled(%d, %d)" dx dy
  | TextInput text -> Printf.sprintf "TextInput(%S)" text
  | TextEditing { text; start; length } ->
      Printf.sprintf "TextEditing(%S, %d, %d)" text start length
  | FileDropped path -> Printf.sprintf "FileDropped(%S)" path
  | WindowResized (w, h) -> Printf.sprintf "WindowResized(%d, %d)" w h
  | WindowFocusLost -> "WindowFocusLost"
  | WindowClosed -> "WindowClosed"
