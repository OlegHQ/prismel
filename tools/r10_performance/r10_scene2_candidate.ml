open Prismel_next_api
open R10_scene2_legacy_equivalent
type t={execution:Prismel_next_execution.t;scenario:R10_scene2_legacy_equivalent.scenario;
  descriptor:R10_scene2_legacy_equivalent.descriptor;mutable frame:int;
  mutable image:Image.t;canvas:Canvas.t option;mutable last_scene:Scene.t option}
let target=function `Headless->Prismel_next_execution.Headless|`Web->Web
let generated_image()=let canvas=Canvas.create_exn~width:96~height:96 in
  Canvas.render canvas Scene.[clear(Color.hex_exn"#0f172a");rounded_rect~at:(4,4)~w:88~h:88~radius:14~fill:(Color.hex_exn"#155e75")~stroke:(Color.hex_exn"#67e8f9")();circle~at:(48,48)~radius:30~fill:(Color.rgba 251 146 60 220)();line~from_:(18,74)~to_:(78,22)~width:5~color:Color.white()];
  let image=Result.get_ok(Canvas.to_image canvas)in Canvas.destroy canvas;image
let create ~target:target_kind ~width ~height scenario =
  let descriptor=R10_scene2_legacy_equivalent.describe scenario~width~height in
  let configuration={Prismel_next_execution.default_configuration with target=target target_kind;
    logical_width=width;logical_height=height;drawable_width=width;drawable_height=height;
    timing=Fixed(1./.120.);title="R10 candidate"}in
  let execution=Prismel_next_execution.create configuration|>Result.get_ok in
  match scenario with
  |Basic->Ok{execution;scenario;descriptor;frame=0;image=generated_image();canvas=None;last_scene=None}
  |Canvas->let canvas=Canvas.create_exn~width~height in Canvas.render canvas Scene.[clear Color.black];
      Ok{execution;scenario;descriptor;frame=0;image=Result.get_ok(Canvas.to_image canvas);canvas=Some canvas;last_scene=None}
  |Pxui->ignore(Prismel_next_execution.destroy execution);Error"PXUI exact interpreter pending pxui_next"
let basic_scene value width height=Scene.[clear(Color.hex_exn"#07111f");rounded_rect~at:(18,18)~w:(width-36)~h:(height-36)~radius:18~fill:(Color.hex_exn"#111827")~stroke:(Color.hex_exn"#475569")();circle~at:(120,150)~radius:72~fill:(Color.hex_exn"#0891b2")();rect~at:(220,74)~w:180~h:120~fill:(Color.rgba 244 63 94 190)();translate 338 292[rotate(float value.frame*.0.01)[polygon[-80,-42;76,-54;98,36;0,74;-88,34]~fill:(Color.hex_exn"#a78bfa")~stroke:Color.white()]];image value.image~at:(470,92)~scale:1.15~angle:(-0.18)~center:(48,48)();bezier[34,404;176,320;282,474;430,382]~steps:48~color:(Color.hex_exn"#fbbf24")();text~at:(32,38)~size:18"Prismel renderer baseline";debug_text~at:(472,430)"FIXED 8x8"]
let canvas_scene value width height=let canvas=Option.get value.canvas and phase=R10_scene2_legacy_equivalent.phase~frame:value.frame in
  Canvas.render canvas Scene.[clear(Color.hex_exn"#07111f");rect~at:(0,0)~w:width~h:height~fill:(Color.hex_exn"#0f172a")();circle~at:(40+((phase*3)mod max 1(width-80)),height/2)~radius:34~fill:(Color.hex_exn"#22d3ee")();translate(width/2)(height/2)[rotate(float phase*.0.02)[rounded_rect~at:(-90,-28)~w:180~h:56~radius:14~fill:(Color.rgba 244 63 94 210)~stroke:Color.white()]];debug_text~at:(16,16)"CANVAS BASELINE"];
  Image.destroy value.image;value.image<-Result.get_ok(Canvas.to_image canvas);Scene.[clear Color.black;image value.image~at:(0,0)()]
let render value ~width ~height =value.frame<-value.frame+1;
  let scene=match value.scenario with Basic->basic_scene value width height|Canvas->canvas_scene value width height|Pxui->assert false in
  Option.iter Scene.Private.release value.last_scene;value.last_scene<-Some scene;
  let ir,resources=Scene.Private.stage~width~height scene|>Result.get_ok in
  let draws=Prismel_next_execution.lower_scene2 value.execution~density:1~resource:(fun id->List.assoc_opt id resources)ir|>Result.get_ok in
  ignore(Prismel_next_execution.step value.execution draws|>Result.get_ok)
let capture value=Prismel_next_execution.capture value.execution|>Result.get_ok
let destroy value=Option.iter Scene.Private.release value.last_scene;Image.destroy value.image;
  Option.iter Canvas.destroy value.canvas;Prismel_next_execution.destroy value.execution|>Result.get_ok
