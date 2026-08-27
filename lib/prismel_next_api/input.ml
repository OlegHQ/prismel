type key = KeyChar of char | ArrowUp | ArrowDown | ArrowLeft | ArrowRight
  | Space | Enter | Escape | Backspace | Tab | Shift | Ctrl | Alt | Meta
  | F1 | F2 | F3 | F4 | F5 | F6 | F7 | F8 | F9 | F10 | F11 | F12
  | Home | End | PageUp | PageDown | Insert | Delete | Unknown of int
type mouse_button = LeftButton | RightButton | MiddleButton | MouseX1 | MouseX2
let keys=ref[]and buttons=ref[]and mouse=ref(0,0)and delta=ref(0,0)
let reset ~mouse:value=keys:=[];buttons:=[];mouse:=value;delta:=(0,0)
let begin_frame()=delta:=(0,0)
let add value values=if List.mem value!values then()else values:=!values@[value]
let remove value values=values:=List.filter((<>)value)!values
let press_key value=add value keys and release_key value=remove value keys
let update_mouse_pos x y=let ox,oy = !mouse and dx,dy = !delta in mouse:=(x,y);delta:=(dx+x-ox,dy+y-oy)
let press_mouse_button value=add value buttons and release_mouse_button value=remove value buttons
let clear_all_input()=keys:=[];buttons:=[];delta:=(0,0)
let is_key_down value=List.mem value!keys
let is_key_up value=not(is_key_down value)
let keys_down() = !keys and mouse_pos() = !mouse and mouse_delta() = !delta
let is_mouse_button_down value=List.mem value!buttons and mouse_buttons_down() = !buttons
let key_to_string=function KeyChar c->String.make 1 c|ArrowUp->"Up"|ArrowDown->"Down"|ArrowLeft->"Left"|ArrowRight->"Right"|Space->"Space"|Enter->"Enter"|Escape->"Escape"|Backspace->"Backspace"|Tab->"Tab"|Shift->"Shift"|Ctrl->"Ctrl"|Alt->"Alt"|Meta->"Meta"|F1->"F1"|F2->"F2"|F3->"F3"|F4->"F4"|F5->"F5"|F6->"F6"|F7->"F7"|F8->"F8"|F9->"F9"|F10->"F10"|F11->"F11"|F12->"F12"|Home->"Home"|End->"End"|PageUp->"PageUp"|PageDown->"PageDown"|Insert->"Insert"|Delete->"Delete"|Unknown n->Printf.sprintf"Unknown(%d)"n
let mouse_button_to_string=function LeftButton->"Left"|RightButton->"Right"|MiddleButton->"Middle"|MouseX1->"X1"|MouseX2->"X2"
