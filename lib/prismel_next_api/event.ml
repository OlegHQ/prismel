type t = KeyPressed of Input.key | KeyReleased of Input.key | MouseMoved of int*int
  | MousePressed of Input.mouse_button*(int*int) | MouseReleased of Input.mouse_button*(int*int)
  | PointerCancelled of Input.mouse_button | MouseScrolled of int*int | TextInput of string
  | TextEditing of {text:string;start:int;length:int} | FileDropped of string
  | WindowResized of int*int | WindowFocusLost | WindowClosed
let source=match Runtime_next_input.create~max_events:4096~max_file_bytes:(16*1024*1024)~logical_width:1~logical_height:1 with Ok x->x|Error e->failwith e
let button=function Runtime_next_input.Left->Input.LeftButton|Right->RightButton|Middle->MiddleButton|X1->MouseX1|X2->MouseX2
let key text=match String.lowercase_ascii text with"up"->Input.ArrowUp|"down"->ArrowDown|"left"->ArrowLeft|"right"->ArrowRight|"space"->Space|"enter"->Enter|"escape"->Escape|value when String.length value=1->KeyChar value.[0]|_->Unknown(Hashtbl.hash text)
let convert=function
  | Runtime_next_input.Pointer_moved(x,y)->Some(MouseMoved(int_of_float x,int_of_float y))
  | Pointer_pressed(b,x,y)->Some(MousePressed(button b,(int_of_float x,int_of_float y)))
  | Pointer_released(b,x,y)->Some(MouseReleased(button b,(int_of_float x,int_of_float y)))
  | Pointer_cancelled b->Some(PointerCancelled(button b))|Wheel(x,y)->Some(MouseScrolled(int_of_float x,int_of_float y))
  | Key_pressed e->Some(KeyPressed(key e.key))|Key_released e->Some(KeyReleased(key e.key))
  | Text_input s->Some(TextInput s)|Text_editing{text;start;length}->Some(TextEditing{text;start;length})
  | File_dropped{name;_}->Some(FileDropped name)|Resized(w,h)->Some(WindowResized(w,h))
  | Focus_lost->Some WindowFocusLost|Quit->Some WindowClosed|Focus_gained|Visibility_changed _->None
let apply=function KeyPressed k->Input.press_key k|KeyReleased k->Input.release_key k|MouseMoved(x,y)->Input.update_mouse_pos x y|MousePressed(b,(x,y))->Input.update_mouse_pos x y;Input.press_mouse_button b|MouseReleased(b,(x,y))->Input.update_mouse_pos x y;Input.release_mouse_button b|PointerCancelled b->Input.release_mouse_button b|WindowFocusLost->Input.clear_all_input()|_->()
let poll_events()=Runtime_next_input.drain source|>List.filter_map convert|>List.map(fun e->apply e;e)
let process_events events state handler=match handler with None->state|Some f->List.fold_left f state events
let handle_events state handler=Input.begin_frame();let events=poll_events()in process_events events state handler,events
let event_to_string=function KeyPressed k->"KeyPressed("^Input.key_to_string k^")"|KeyReleased k->"KeyReleased("^Input.key_to_string k^")"|MouseMoved(x,y)->Printf.sprintf"MouseMoved(%d,%d)"x y|MousePressed _->"MousePressed"|MouseReleased _->"MouseReleased"|PointerCancelled _->"PointerCancelled"|MouseScrolled _->"MouseScrolled"|TextInput _->"TextInput"|TextEditing _->"TextEditing"|FileDropped _->"FileDropped"|WindowResized _->"WindowResized"|WindowFocusLost->"WindowFocusLost"|WindowClosed->"WindowClosed"
module Private=struct let push=Runtime_next_input.push source end
