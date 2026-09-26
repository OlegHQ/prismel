open Prismel

let require condition message=if not condition then failwith message
let read path=let channel=open_in_bin path in Fun.protect~finally:(fun()->close_in channel)
  (fun()->really_input_string channel(in_channel_length channel))
let normalize value=String.trim value
let run () =
  if Array.length Sys.argv<>10 then invalid_arg"eight interface paths required";
  for index=0 to 3 do
    let legacy=read Sys.argv.(2+index)and staged=read Sys.argv.(6+index)in
    require(normalize legacy=normalize staged)("interface drift: "^Sys.argv.(2+index))
  done;
  let open Input in
  let open Event in
  let events=[KeyPressed Space;MouseMoved(4.,8.);MouseScrolled (1., (-2.));
    TextEditing{text="ime";start=0;length=3};WindowResized(8,9);WindowClosed]in
  let frame={Frame.width=4;height=3;size=(4,3);drawable_width=8;drawable_height=6;
    drawable_size=(8,6);pixel_scale=(2.,2.);time=1.;dt=0.5;fps=2.;count=7;
    mouse=(4.,8.);mouse_delta=(3.,6.);keys=[Space];mouse_buttons=[MouseX2];events}in
  require(Frame.key_down Space frame&&Frame.mouse_down MouseX2 frame
    &&Frame.has_event(function Event.WindowClosed->true|_->false)frame)"frame facts";
  print_endline"next core interfaces: exact Event/Input/Frame declarations and behavior"
