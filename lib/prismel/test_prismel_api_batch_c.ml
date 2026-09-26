open Prismel
let run () =
  (match Sketch.set_cursor `Horizontal_resize with
   | Error _ -> () | Ok () -> failwith "cursor without an active sketch");
  let events=[Event.MousePressed(Input.LeftButton,(2.,3.));Event.MouseMoved(4.,8.)]in
  let frame={Frame.width=4;height=3;size=(4,3);drawable_width=8;drawable_height=6;drawable_size=(8,6);pixel_scale=(2.,2.);time=1.;dt=0.5;fps=2.;count=1;mouse=(4.,8.);mouse_delta=(-1.,1.);keys=[];mouse_buttons=[Input.LeftButton];events}in
  if not(Frame.mouse_down Input.LeftButton frame)||not(Frame.has_event(function Event.MouseMoved _->true|_->false)frame)then failwith"frame";
  let scene=[Scene.clear Color.black;Scene.rect~at:(0,0)~w:4~h:3~fill:Color.red();
    Scene.text_input_region~at:(1,1)~w:2~h:1~focused:true~cursor:1()]in
  let ir=Result.get_ok(Scene.Private.to_ir scene)in
  if Array.length(Scene_command.Render_ir.commands ir)<>2||Scene.Private.text_regions scene<>[1,1,2,1,true,1]then failwith"scene lowering";
  (match Scene.text_input_region~at:(0,0)~w:1~h:1~cursor:(-1)() with
   | _ -> failwith"negative IME cursor accepted"
   | exception Invalid_argument _ -> ());
  print_endline"Prismel batch C: Event/Input/Frame/Scene fixtures passed"
