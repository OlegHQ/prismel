open Prismel

let require condition message=if not condition then failwith message
let read path=let channel=open_in_bin path in Fun.protect~finally:(fun()->close_in channel)
  (fun()->really_input_string channel(in_channel_length channel))
let normalize value=String.trim value
let ()=
  if Array.length Sys.argv<>9 then invalid_arg"eight interface paths required";
  for index=0 to 3 do
    let legacy=read Sys.argv.(1+index)and staged=read Sys.argv.(5+index)in
    require(normalize legacy=normalize staged)("interface drift: "^Sys.argv.(1+index))
  done;
  let open Input in
  let keys=[KeyChar 'a';ArrowUp;ArrowDown;ArrowLeft;ArrowRight;Space;Enter;Escape;
    Backspace;Tab;Shift;Ctrl;Alt;Meta;F1;F2;F3;F4;F5;F6;F7;F8;F9;F10;F11;F12;
    Home;End;PageUp;PageDown;Insert;Delete;Unknown 42]in
  require(List.for_all(fun key->Input.key_to_string key<>"")keys)"key name table";
  Input.reset~mouse:(1,2);Input.press_key Input.Space;Input.press_mouse_button Input.MouseX2;
  Input.update_mouse_pos 4 8;
  require(Input.keys_down()=[Space]&&Input.mouse_buttons_down()=[MouseX2]
    &&Input.mouse_delta()=(3,6))"input state semantics";
  let open Event in
  let events=[KeyPressed Space;MouseMoved(4,8);MouseScrolled(1,-2);
    TextEditing{text="ime";start=0;length=3};WindowResized(8,9);WindowClosed]in
  require(Event.process_events events 0(Some(fun count _->count+1))=List.length events)
    "event order";
  require(Event.event_to_string(List.hd events)="KeyPressed(Space)")"event format";
  let frame={Frame.width=4;height=3;size=(4,3);drawable_width=8;drawable_height=6;
    drawable_size=(8,6);pixel_scale=(2.,2.);time=1.;dt=0.5;fps=2.;count=7;
    mouse=(4,8);mouse_delta=(3,6);keys=[Space];mouse_buttons=[MouseX2];events}in
  require(Frame.key_down Space frame&&Frame.mouse_down MouseX2 frame
    &&Frame.has_event(function Event.WindowClosed->true|_->false)frame)"frame facts";
  require(Time.Easing.linear 0.25=0.25&&Time.smoothstep 0.=0.
    &&Time.smoothstep 1.=1.&&Time.elapsed_fraction 0. 0.=1.)"time helpers";
  print_endline"next core interfaces: exact Event/Input/Frame/Time declarations and behavior"
