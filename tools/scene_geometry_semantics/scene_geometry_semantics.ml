open Prismel_next_api

let get = function Ok value -> value | Error _ -> failwith "geometry fixture failed"
let rgba (color:Color.t)=Int32.logor(Int32.shift_left(Int32.of_int color.r)24)
  (Int32.logor(Int32.shift_left(Int32.of_int color.g)16)
    (Int32.logor(Int32.shift_left(Int32.of_int color.b)8)(Int32.of_int color.a)))
let pixel surface x y=get(Raster2.Surface.get_rgba surface~x~y)
let require condition message=if not condition then failwith message
let render scene =
  let ir=get(Scene.Private.to_ir scene)and surface=get(Raster2.Surface.create~width:40~height:32())in
  Raster2.Surface.clear surface(rgba Color.black);
  get(Raster2.Consumer.execute~lookup:(fun _->None)~target:surface ir);ir,surface

let () =
  let rounded=Scene.rounded_rect~at:(2,2)~w:20~h:16~radius:6~fill:Color.red()in
  let thick=Scene.line~from_:(2,26)~to_:(30,26)~width:6~color:Color.blue()in
  let curve=Scene.bezier[(2,26);(16,2);(30,26)]~steps:32~color:Color.green()in
  let scene=[Scene.clear Color.black;rounded;thick;curve;
    Scene.clip~at:(32,0)~w:4~h:8[Scene.translate 30 0[Scene.line~from_:(0,4)~to_:(12,4)~width:4~color:Color.white()]];
    Scene.rect~at:(34,3)~w:2~h:2~fill:Color.red()]in
  require(Raster2.Render_ir.serialize(get(Scene.Private.to_ir[Scene.line~from_:(0,0)~to_:(2,0)~width:0()]))=
    Raster2.Render_ir.serialize(get(Scene.Private.to_ir[Scene.line~from_:(0,0)~to_:(2,0)~width:1()])))
    "legacy line-width clamp drift";
  require(Raster2.Render_ir.serialize(get(Scene.Private.to_ir[Scene.bezier[(0,0);(2,2)]~steps:0()]))=
    Raster2.Render_ir.serialize(get(Scene.Private.to_ir[Scene.bezier[(0,0);(2,2)]~steps:1()])))
    "legacy Bezier-step clamp drift";
  let first_ir,first=render scene in
  require(pixel first 2 2=rgba Color.black)"rounded corner was not clipped by radius";
  require(pixel first 8 4=rgba Color.red)"rounded shoulder missing";
  require(pixel first 10 23=rgba Color.blue)"thick line upper edge missing";
  require(pixel first 10 22=rgba Color.black)"thick line exceeded requested width";
  require(pixel first 16 14=rgba Color.green)"Bezier curve did not pass its quadratic midpoint";
  require(pixel first 16 2<>rgba Color.green)"Bezier regressed to control polyline";
  require(pixel first 33 4=rgba Color.white)"transformed clipped geometry missing";
  require(pixel first 34 4=rgba Color.red)"later geometry did not preserve order";
  let encoded=Raster2.Render_ir.serialize first_ir in
  List.iter(fun frame->let ir,surface=render scene in
    require(Raster2.Render_ir.serialize ir=encoded)(Printf.sprintf"frame %d IR drift"frame);
    require(pixel surface 16 14=rgba Color.green)(Printf.sprintf"frame %d pixel drift"frame))
    [1;2;60;600];
  print_endline"next Scene geometry: radius/width/Bezier transform+clip frames1/2/60/600"
