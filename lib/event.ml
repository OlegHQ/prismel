(* Event module for handling input events *)

(* Event type representing all framework events *)
type t =
  | KeyPressed of Input.key
  | KeyReleased of Input.key
  | MouseMoved of (int * int)                                (* new mouse position *)
  | MousePressed of Input.mouse_button * (int * int)        (* button and position *)
  | MouseReleased of Input.mouse_button * (int * int)       (* button and position *)
  | MouseScrolled of (int * int)                             (* scroll delta x,y *)
  | WindowResized of (int * int)                             (* new width and height *)
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
  | 1 -> Input.LeftButton      (* SDL_BUTTON_LEFT *)
  | 2 -> Input.MiddleButton    (* SDL_BUTTON_MIDDLE *)
  | 3 -> Input.RightButton     (* SDL_BUTTON_RIGHT *)
  | 4 -> Input.MouseX1         (* SDL_BUTTON_X1 *)
  | 5 -> Input.MouseX2         (* SDL_BUTTON_X2 *)
  | _ -> Input.LeftButton      (* Default fallback *)

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
      Some (MousePressed (sdl_button_to_input_button button, (x, y)))

  | `Mouse_button_up ->
      let button = Event.get sdl_event Event.mouse_button_button in
      let x = Event.get sdl_event Event.mouse_button_x in
      let y = Event.get sdl_event Event.mouse_button_y in
      Some (MouseReleased (sdl_button_to_input_button button, (x, y)))

  | `Mouse_wheel ->
      let x = Event.get sdl_event Event.mouse_wheel_x in
      let y = Event.get sdl_event Event.mouse_wheel_y in
      Some (MouseScrolled (x, y))

  | `Window_event ->
      (match Event.window_event_enum (Event.get sdl_event Event.window_event_id) with
       | `Resized ->
            let w = Event.get sdl_event Event.window_data1 in
           let h = Event.get sdl_event Event.window_data2 in
           Some (WindowResized (Int32.to_int w, Int32.to_int h))
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
  | MouseScrolled _ -> () (* No persistent state for scroll *)
  | WindowResized _ -> () (* Handled by renderer/window management *)
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
  poll_loop []

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
  | MouseScrolled (dx, dy) -> Printf.sprintf "MouseScrolled(%d, %d)" dx dy
  | WindowResized (w, h) -> Printf.sprintf "WindowResized(%d, %d)" w h
  | WindowClosed -> "WindowClosed"
