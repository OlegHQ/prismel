type t = KeyPressed of Input.key | KeyReleased of Input.key | MouseMoved of (int*int)
  | MousePressed of Input.mouse_button*(int*int) | MouseReleased of Input.mouse_button*(int*int)
  | PointerCancelled of Input.mouse_button | MouseScrolled of (float*float) | TextInput of string
  | TextEditing of {text:string;start:int;length:int} | FileDropped of string
  | WindowResized of (int*int) | WindowFocusLost | WindowClosed
let source=match Runtime_next_input.create~max_events:4096~max_file_bytes:(16*1024*1024)~logical_width:1~logical_height:1 with Ok x->x|Error e->failwith e
let button=function Runtime_next_input.Left->Input.LeftButton|Right->RightButton|Middle->MiddleButton|X1->MouseX1|X2->MouseX2
let key text=match String.lowercase_ascii text with
  |"arrowup"->Input.ArrowUp|"arrowdown"->ArrowDown|"arrowleft"->ArrowLeft|"arrowright"->ArrowRight
  |"space"->Space|"enter"->Enter|"escape"->Escape|"backspace"->Backspace|"tab"->Tab
  |"shift"|"left shift"|"right shift"->Shift|"ctrl"|"control"|"left ctrl"|"right ctrl"->Ctrl
  |"alt"|"left alt"|"right alt"->Alt|"meta"|"gui"|"left gui"|"right gui"->Meta
  |"f1"->F1|"f2"->F2|"f3"->F3|"f4"->F4|"f5"->F5|"f6"->F6
  |"f7"->F7|"f8"->F8|"f9"->F9|"f10"->F10|"f11"->F11|"f12"->F12
  |"home"->Home|"end"->End|"pageup"|"page up"->PageUp|"pagedown"|"page down"->PageDown
  |"insert"->Insert|"delete"->Delete
  |value when String.length value=1->KeyChar value.[0]
  |_->Unknown(Hashtbl.hash text)
let convert=function
  | Runtime_next_input.Pointer_moved(x,y)->Some(MouseMoved(int_of_float x,int_of_float y))
  | Pointer_pressed(b,x,y)->Some(MousePressed(button b,(int_of_float x,int_of_float y)))
  | Pointer_released(b,x,y)->Some(MouseReleased(button b,(int_of_float x,int_of_float y)))
  | Pointer_cancelled b->Some(PointerCancelled(button b))|Wheel(x,y)->Some(MouseScrolled(x,y))
  | Key_pressed e->Some(KeyPressed(key e.key))|Key_released e->Some(KeyReleased(key e.key))
  | Text_input s->Some(TextInput s)|Text_editing{text;start;length}->Some(TextEditing{text;start;length})
  | File_dropped{name;_}->Some(FileDropped name)|Resized(w,h)->Some(WindowResized(w,h))
  | Focus_lost->Some WindowFocusLost|Quit->Some WindowClosed|Focus_gained|Visibility_changed _->None
let apply=function KeyPressed k->Input.press_key k|KeyReleased k->Input.release_key k|MouseMoved(x,y)->Input.update_mouse_pos x y|MousePressed(b,(x,y))->Input.update_mouse_pos x y;Input.press_mouse_button b|MouseReleased(b,(x,y))->Input.update_mouse_pos x y;Input.release_mouse_button b|PointerCancelled b->Input.release_mouse_button b|WindowFocusLost->Input.clear_all_input()|_->()
let configure ~logical_width ~logical_height =
  match Runtime_next_input.set_extent source ~logical_width ~logical_height with
  | Ok () -> ()
  | Error message -> invalid_arg ("Event.configure: " ^ message)
(* In relative mode the frame's [mouse_delta] is the summed device motion
   rather than absolute differences, which stop at the window edge. *)
let poll_events()=
  Input.begin_frame();Runtime_next_input.begin_frame source;
  (match Runtime_next_input_sdl3.pump source with Ok()->()|Error _->());
  let events=Runtime_next_input.drain source|>List.filter_map convert|>List.map(fun e->apply e;e)in
  if Runtime_next_input.relative source then begin
    let dx,dy=(Runtime_next_input.snapshot source).mouse_delta in
    Input.set_mouse_delta(int_of_float(Float.round dx),int_of_float(Float.round dy))
  end;
  events
module Private=struct let set_relative enabled=Runtime_next_input.set_relative source enabled let key_of_name=key end
let process_events events state handler=match handler with None->state|Some f->List.fold_left f state events
let handle_events state handler=let events=poll_events()in process_events events state handler,events
let event_to_string=function
  |KeyPressed key->"KeyPressed("^Input.key_to_string key^")"
  |KeyReleased key->"KeyReleased("^Input.key_to_string key^")"
  |MouseMoved(x,y)->Printf.sprintf"MouseMoved(%d, %d)"x y
  |MousePressed(button,(x,y))->Printf.sprintf"MousePressed(%s, (%d, %d))"(Input.mouse_button_to_string button)x y
  |MouseReleased(button,(x,y))->Printf.sprintf"MouseReleased(%s, (%d, %d))"(Input.mouse_button_to_string button)x y
  |PointerCancelled button->Printf.sprintf"PointerCancelled(%s)"(Input.mouse_button_to_string button)
  |MouseScrolled(dx,dy)->Printf.sprintf"MouseScrolled(%g, %g)"dx dy
  |TextInput text->Printf.sprintf"TextInput(%S)"text
  |TextEditing{text;start;length}->Printf.sprintf"TextEditing(%S, %d, %d)"text start length
  |FileDropped path->Printf.sprintf"FileDropped(%S)"path
  |WindowResized(w,h)->Printf.sprintf"WindowResized(%d, %d)"w h
  |WindowFocusLost->"WindowFocusLost"|WindowClosed->"WindowClosed"
