open Prismel_next_api
open R10_scene2_legacy_equivalent
let execution_ok=function Ok value->value|Error error->failwith(Format.asprintf"%a"Prismel_next_execution.pp_error error)
let resource_ok=function Ok value->value|Error error->failwith(Format.asprintf"%a"Prismel_next_resources.pp_error error)
type t={execution:Prismel_next_execution.t;scenario:R10_scene2_legacy_equivalent.scenario;
  descriptor:R10_scene2_legacy_equivalent.descriptor;mutable frame:int;
  mutable image:Image.t option;canvas:Prismel_next_resources.Canvas.t option;
  ui:Pxui_next.t option}
let submit_scene execution ~width ~height scene =
  Fun.protect ~finally:(fun()->Scene.Private.release scene)(fun()->
    let ir,resources=Scene.Private.stage~width~height scene|>Result.get_ok in
    let draws=Prismel_next_execution.lower_scene2 execution~density:1
      ~resource:(fun id->List.assoc_opt id resources)ir|>Result.get_ok in
    ignore(execution_ok(Prismel_next_execution.step execution draws)))
let generated_image execution ~restore_width ~restore_height =
  let width=96 and height=96 in
  execution_ok(Prismel_next_execution.resize execution~logical_width:width
    ~logical_height:height~drawable_width:width~drawable_height:height);
  Fun.protect
    ~finally:(fun()->execution_ok(Prismel_next_execution.resize execution
      ~logical_width:restore_width~logical_height:restore_height
      ~drawable_width:restore_width~drawable_height:restore_height))
    (fun()->
      submit_scene execution~width~height Scene.[
        clear(Color.hex_exn"#0f172a");
        rounded_rect~at:(4,4)~w:88~h:88~radius:14
          ~fill:(Color.hex_exn"#155e75")~stroke:(Color.hex_exn"#67e8f9")();
        circle~at:(48,48)~radius:30~fill:(Color.rgba 251 146 60 220)();
        line~from_:(18,74)~to_:(78,22)~width:5~color:Color.white()];
      let canvas=resource_ok(Prismel_next_resources.Canvas.create~width~height)in
      Fun.protect~finally:(fun()->ignore(Prismel_next_resources.Canvas.destroy canvas))(fun()->
        resource_ok(Prismel_next_resources.Canvas.replace_pixels canvas
          (execution_ok(Prismel_next_execution.capture execution)));
        Prismel_next_resources.Canvas.capture canvas|>resource_ok|>Image.Private.of_resource))
let create ~width ~height scenario =
  let descriptor=R10_scene2_legacy_equivalent.describe scenario~width~height in
  let configuration={Prismel_next_execution.default_configuration with
    logical_width=width;logical_height=height;drawable_width=width;drawable_height=height;
    timing=Fixed(1./.60.);title="R10 candidate"}in
  let execution=Prismel_next_execution.create configuration|>Result.get_ok in
  match scenario with
  |Basic->Ok{execution;scenario;descriptor;frame=0;
      image=Some(generated_image execution~restore_width:width~restore_height:height);
      canvas=None;ui=None}
  |Canvas->let canvas=resource_ok(Prismel_next_resources.Canvas.create~width~height)in
      resource_ok(Prismel_next_resources.Canvas.clear canvas 0x000000ffl);
      Ok{execution;scenario;descriptor;frame=0;
        image=Some(Prismel_next_resources.Canvas.capture canvas|>resource_ok|>Image.Private.of_resource);
        canvas=Some canvas;ui=None}
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
let update_canvas value ~width ~height =
  let phase=R10_scene2_legacy_equivalent.phase~frame:value.frame in
  submit_scene value.execution~width~height Scene.[
    clear(Color.hex_exn"#07111f");
    rect~at:(0,0)~w:width~h:height~fill:(Color.hex_exn"#0f172a")();
    circle~at:(40+((phase*3)mod max 1(width-80)),height/2)
      ~radius:34~fill:(Color.hex_exn"#22d3ee")();
    translate(width/2)(height/2)[rotate(float phase*.0.02)[
      rounded_rect~at:(-90,-28)~w:180~h:56~radius:14
        ~fill:(Color.rgba 244 63 94 210)~stroke:Color.white()]];
    debug_text~at:(16,16)"CANVAS BASELINE"];
  let canvas=Option.get value.canvas in
  resource_ok(Prismel_next_resources.Canvas.replace_pixels canvas
    (execution_ok(Prismel_next_execution.capture value.execution)));
  let next=Prismel_next_resources.Canvas.capture canvas|>resource_ok|>Image.Private.of_resource in
  Option.iter Image.destroy value.image;
  value.image<-Some next
let pxui_scene value=Scene.[clear(Color.hex_exn"#07111f");text~at:(24,24)~size:20"PXUI render baseline";rounded_rect~at:(18,62)~w:306~h:382~radius:12~fill:(Color.hex_exn"#111827")~stroke:(Color.hex_exn"#334155")();circle~at:(168,236)~radius:94~fill:(Color.hex_exn"#155e75")();debug_text~at:(88,420)"GRAPH / INSPECTOR"]@Pxui_next.scene(Option.get value.ui)
let render value ~width ~height =value.frame<-value.frame+1;
  if value.scenario=Canvas then update_canvas value~width~height;
  let scene=match value.scenario with Basic->basic_scene value width height|Canvas->canvas_scene value width height|Pxui->pxui_scene value|Scene3->assert false in
  submit_scene value.execution~width~height scene
let render_canonical value ~width ~height =
  value.frame <- 0;
  render value ~width ~height
let capture value=execution_ok(Prismel_next_execution.capture value.execution)
let stats value=execution_ok(Prismel_next_execution.stats value.execution)
let presentation_facts value=
  execution_ok(Prismel_next_execution.presentation_facts value.execution)
let destroy value=Option.iter Image.destroy value.image;
  Option.iter(fun canvas->ignore(Prismel_next_resources.Canvas.destroy canvas))value.canvas;
  execution_ok(Prismel_next_execution.destroy value.execution)
