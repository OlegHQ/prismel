type t = KeyPressed of Input.key | KeyReleased of Input.key | MouseMoved of (float*float)
  | MousePressed of Input.mouse_button*(float*float) | MouseReleased of Input.mouse_button*(float*float)
  | PointerCancelled of Input.mouse_button | MouseScrolled of (float*float) | TextInput of string
  | TextEditing of {text:string;start:int;length:int} | FileDropped of string
  | WindowResized of (int*int) | WindowFocusLost | WindowClosed
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
module Private=struct let key_of_name=key end
