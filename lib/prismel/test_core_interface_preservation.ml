open Prismel

let require condition message=if not condition then failwith message
let run () =
  let open Input in
  let open Event in
  let events=[KeyPressed Space;MouseMoved(4.,8.);MouseScrolled (1., (-2.));
    TextEditing{text="ime";start=0;length=3};WindowResized(8,9);WindowClosed]in
  let frame={Frame.width=4;height=3;size=(4,3);drawable_width=8;drawable_height=6;
    drawable_size=(8,6);pixel_scale=(2.,2.);time=1.;dt=0.5;fps=2.;count=7;
    mouse=(4.,8.);mouse_delta=(3.,6.);keys=[Space];mouse_buttons=[MouseX2];events}in
  require(Frame.key_down Space frame&&Frame.mouse_down MouseX2 frame
    &&Frame.has_event(function Event.WindowClosed->true|_->false)frame)"frame facts";
  print_endline"core Event/Input/Frame facts"
