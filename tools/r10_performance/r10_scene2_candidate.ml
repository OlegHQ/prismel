open Prismel_next_api
open R10_scene2_legacy_equivalent
let execution_ok=function Ok value->value|Error error->failwith(Format.asprintf"%a"Prismel_next_execution.pp_error error)
type t={execution:Prismel_next_execution.t;scenario:R10_scene2_legacy_equivalent.scenario;
  descriptor:R10_scene2_legacy_equivalent.descriptor;mutable frame:int;
  mutable image:Image.t option;canvas:Canvas.t option;ui:Pxui_next.t option}
let target=function `Native->Prismel_next_execution.Native
let fill canvas ~width ~height color=for y=0 to height-1 do for x=0 to width-1 do
  Canvas.set_pixel canvas~x~y color done done
let canvas_background=Color.hex_exn"#0f172a"
let fill_canvas canvas ~width ~height=
  fill canvas~width~height canvas_background;
  let center=width/2 in
  for y=0 to height-1 do for x=0 to width-1 do
    let dx=x-center and dy=y-(height/2)in
    if dx*dx+dy*dy<=34*34 then Canvas.set_pixel canvas~x~y Color.cyan
  done done
let generated_image()=let canvas=Canvas.create_exn~width:96~height:96 in
  for y=0 to 95 do for x=0 to 95 do
    Canvas.set_pixel canvas~x~y(Color.rgb((x*255)/95)((y*255)/95)160)
  done done;
  let image=Result.get_ok(Canvas.to_image canvas)in Canvas.destroy canvas;image
let create ~target:target_kind ~width ~height scenario =
  let descriptor=R10_scene2_legacy_equivalent.describe scenario~width~height in
  let configuration={Prismel_next_execution.default_configuration with target=target target_kind;
    logical_width=width;logical_height=height;drawable_width=width;drawable_height=height;
    timing=Fixed(1./.60.);title="R10 candidate"}in
  let execution=Prismel_next_execution.create configuration|>Result.get_ok in
  match scenario with
  |Basic->Ok{execution;scenario;descriptor;frame=0;image=Some(generated_image());canvas=None;ui=None}
  |Canvas->let canvas=Canvas.create_exn~width~height in fill_canvas canvas~width~height;
      Ok{execution;scenario;descriptor;frame=0;image=Some(Result.get_ok(Canvas.to_image canvas));canvas=Some canvas;ui=None}
  |Pxui->let ui=ref(Pxui_next.create~x:348~y:16~width:276~row_height:29~padding:8~max_height:448())in
      for index=0 to 3 do ui:=Pxui_next.accordion~name:("section-"^string_of_int index)
        ~label:("Section "^string_of_int(index+1))~expanded:true(fun ui->ui
          |>Pxui_next.toggle~name:("toggle-"^string_of_int index)~label:"Enabled"~value:(index land 1=0)
          |>Pxui_next.slider~name:("slider-"^string_of_int index)~label:"Amount"~min:(-1.)~max:1.~value:(float index/.4.)
          |>Pxui_next.int_slider~name:("steps-"^string_of_int index)~label:"Steps"~min:1~max:64~value:(8+index)
          |>Pxui_next.choice~name:("choice-"^string_of_int index)~label:"Mode"~options:["Solid";"Wire";"Points"]~selected:(index mod 3))!ui done;
      Ok{execution;scenario;descriptor;frame=0;image=None;canvas=None;ui=Some!ui}
  |Scene3->ignore(Prismel_next_execution.destroy execution);Error"Scene3 uses its canonical interpreter"
let basic_scene value width height=Scene.[clear(Color.hex_exn"#07111f");rounded_rect~at:(18,18)~w:(width-36)~h:(height-36)~radius:18~fill:(Color.hex_exn"#111827")~stroke:(Color.hex_exn"#475569")();circle~at:(120,150)~radius:72~fill:(Color.hex_exn"#0891b2")();rect~at:(220,74)~w:180~h:120~fill:(Color.rgba 244 63 94 190)();translate 338 292[rotate(float value.frame*.0.01)[polygon[-80,-42;76,-54;98,36;0,74;-88,34]~fill:(Color.hex_exn"#a78bfa")~stroke:Color.white()]];image(Option.get value.image)~at:(470,92)~scale:1.15~angle:(-0.18)~center:(48,48)();bezier[34,404;176,320;282,474;430,382]~steps:48~color:(Color.hex_exn"#fbbf24")();text~at:(32,38)~size:18"Prismel renderer baseline";debug_text~at:(472,430)"FIXED 8x8"]
let canvas_scene value _width _height=
  Scene.[clear Color.black;image(Option.get value.image)~at:(0,0)()]
let pxui_scene value=Scene.[clear(Color.hex_exn"#07111f");text~at:(24,24)~size:20"PXUI render baseline";rounded_rect~at:(18,62)~w:306~h:382~radius:12~fill:(Color.hex_exn"#111827")~stroke:(Color.hex_exn"#334155")();circle~at:(168,236)~radius:94~fill:(Color.hex_exn"#155e75")();debug_text~at:(88,420)"GRAPH / INSPECTOR"]@Pxui_next.scene(Option.get value.ui)
let render value ~width ~height =value.frame<-value.frame+1;
  let scene=match value.scenario with Basic->basic_scene value width height|Canvas->canvas_scene value width height|Pxui->pxui_scene value|Scene3->assert false in
  Fun.protect~finally:(fun()->Scene.Private.release scene)(fun()->
    let ir,resources=Scene.Private.stage~width~height scene|>Result.get_ok in
    let draws=Prismel_next_execution.lower_scene2 value.execution~density:1~resource:(fun id->List.assoc_opt id resources)ir|>Result.get_ok in
    ignore(execution_ok(Prismel_next_execution.step value.execution draws)))
let render_canonical value ~width ~height =
  value.frame <- 0;
  render value ~width ~height
let capture value=execution_ok(Prismel_next_execution.capture value.execution)
let stats value=execution_ok(Prismel_next_execution.stats value.execution)
let destroy value=Option.iter Image.destroy value.image;
  Option.iter Canvas.destroy value.canvas;execution_ok(Prismel_next_execution.destroy value.execution)
