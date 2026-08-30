open Prismel_next_api

let require condition message=if not condition then failwith message
let frame events : Frame.t={width=160;height=220;size=(160,220);drawable_width=160;
  drawable_height=220;drawable_size=(160,220);pixel_scale=(1.,1.);time=1.;dt=1./.60.;fps=60.;count=1;
  mouse=(0,0);mouse_delta=(0,0);keys=[];mouse_buttons=[];events}
let () =
  let ui=Pxui_next.create~x:4~y:4~width:148~row_height:29~padding:4()|>
    Pxui_next.label~text:"PXUI next"|>Pxui_next.toggle~name:"enabled"~label:"Enabled"~value:false|>
    Pxui_next.slider~name:"amount"~label:"Amount"~min:0.~max:1.~value:0.25|>
    Pxui_next.text_field~name:"name"~label:"Name"~value:"next"in
  let rec find_toggle y x =
    if y>=220 then failwith"toggle hit region missing"
    else if x>=160 then find_toggle(y+4)0
    else let candidate,changes=Pxui_next.update_frame ui(frame[
      Event.MousePressed(Input.LeftButton,(x,y));MouseReleased(Input.LeftButton,(x,y))])in
      if List.exists(function Pxui_next.Toggled("enabled",true)->true|_->false)changes
      then candidate,changes else find_toggle y(x+8)in
  let ui,pressed=find_toggle 0 0 in
  require(List.exists(function Pxui_next.Toggled("enabled",true)->true|_->false)pressed)"toggle interaction";
  require(Pxui_next.toggle_value ui"enabled"=Some true)"toggle state";
  let scene=Pxui_next.scene ui in
  require(Pxui_next.scene ui==scene)"stable UI did not reuse bounded Scene description";
  let first=Result.get_ok(Scene.Private.to_ir scene)in
  let hash=Printf.sprintf"%016Lx"(Scene_command.Render_ir.hash first)in
  require(hash="37db9a43f0e432bd")"PXUI-next exact Scene hash drift";
  List.iter(fun checkpoint->let ir=Result.get_ok(Scene.Private.to_ir scene)in
    require(Scene_command.Render_ir.serialize ir=Scene_command.Render_ir.serialize first)(Printf.sprintf"frame %d drift"checkpoint))
    [1;2;60;600];
  require(Array.length(Scene_command.Render_ir.commands first)>12)"representative layout commands";
  let changed=Pxui_next.set_toggle_value ui"enabled"false in
  let changed_scene=Pxui_next.scene changed in
  require(changed_scene!=scene)"functional widget update reused stale Scene";
  let changed_ir=Result.get_ok(Scene.Private.to_ir changed_scene)in
  require(Scene_command.Render_ir.serialize changed_ir<>Scene_command.Render_ir.serialize first)
    "functional widget update did not change exact Scene";
  Pxui_next.add_label ui~text:"compatibility mutation";
  let mutated_scene=Pxui_next.scene ui in
  require(mutated_scene!=scene)"compatibility widget mutation reused stale Scene";
  ignore(Result.get_ok(Scene.Private.to_ir mutated_scene));
  Scene.Private.release changed_scene;
  Scene.Private.release mutated_scene;
  Scene.Private.release scene;
  Printf.printf"pxui_next: interaction/layout/Scene frames1/2/60/600 hash=%s\n"hash
