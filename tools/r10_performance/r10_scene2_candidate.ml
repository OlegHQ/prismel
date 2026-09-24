open Prismel_next_api
open R10_scene2_legacy_equivalent
let execution_ok=function Ok value->value|Error error->failwith(Format.asprintf"%a"Prismel_next_execution.pp_error error)
type t={execution:Prismel_next_execution.t;scenario:R10_scene2_legacy_equivalent.scenario;
  descriptor:R10_scene2_legacy_equivalent.descriptor;mutable frame:int;
  mutable image:Image.t option;canvas:Canvas.t option;
  setup_canvas_stats:Canvas.Private.native_stats option;
  ui:Pxui.Ui.t option}
let submit_scene execution ~width ~height scene =
  let active=ref None in
  let submission,batch,clear=try
    Fun.protect ~finally:(fun()->Scene.Private.release scene)(fun()->
      let staged=Scene.Private.stage_native~width~height scene|>Result.get_ok in
      let facts=execution_ok(Prismel_next_execution.presentation_facts execution)in
      let density=max 1(int_of_float(Float.round facts.pixel_density))in
      let submission=execution_ok
        (Prismel_next_execution.Private.begin_submission execution)in
      active:=Some submission;
      let batch=execution_ok(Prismel_next_execution.Private.lower_scene2 submission
        ~density~resource:(fun id->List.assoc_opt id staged.resources)staged.scene2)in
      (* PXUI paints through native instance layers above the Scene2 batch. *)
      let ui_batches=List.filter_map(function
        |Scene.Private.Ui_layer(ui,resources)->Some(execution_ok
            (Prismel_next_execution.Private.lower_ui submission~density
              ~resource:(fun id->List.assoc_opt id resources)ui))
        |_->None)staged.layers in
      submission,batch::ui_batches,staged.clear)
  with exn->
    Option.iter Prismel_next_execution.Private.cancel !active;
    raise exn in
  ignore(execution_ok(Prismel_next_execution.Private.step~clear submission batch))
let generated_image () =
  let width=96 and height=96 in
  let canvas=Canvas.create_exn~width~height in
  Fun.protect~finally:(fun()->Canvas.destroy canvas)(fun()->
      Canvas.render canvas Scene.[
        clear(Color.hex_exn"#0f172a");
        rounded_rect~at:(4,4)~w:88~h:88~radius:14
          ~fill:(Color.hex_exn"#155e75")~stroke:(Color.hex_exn"#67e8f9")();
        circle~at:(48,48)~radius:30~fill:(Color.rgba 251 146 60 220)();
        line~from_:(18,74)~to_:(78,22)~width:5~color:Color.white()];
      Result.get_ok(Canvas.to_image canvas),Canvas.Private.native_stats canvas)
let create ~width ~height scenario =
  let descriptor=R10_scene2_legacy_equivalent.describe scenario~width~height in
  let configuration={Prismel_next_execution.default_configuration with
    logical_width=width;logical_height=height;drawable_width=width;drawable_height=height;
    timing=Fixed(1./.60.);vsync=false;title="R10 candidate"}in
  let execution=Prismel_next_execution.create configuration|>Result.get_ok in
  match scenario with
  |Basic->let image,setup_canvas_stats=generated_image()in
      Ok{execution;scenario;descriptor;frame=0;image=Some image;
      canvas=None;setup_canvas_stats=Some setup_canvas_stats;ui=None}
  |Canvas->let canvas=Canvas.create_exn~width~height in
      Canvas.render canvas Scene.[clear Color.black];
      Ok{execution;scenario;descriptor;frame=0;
        image=Some(Result.get_ok(Canvas.to_image canvas));
        canvas=Some canvas;setup_canvas_stats=Some(Canvas.Private.native_stats canvas);
        ui=None}
  |Pxui->
      (* Four expanded kit sections in a bounded, padded panel. *)
      let ui=Pxui.Ui.create()in
      let frame:Frame.t={width;height;size=width,height;drawable_width=width;
        drawable_height=height;drawable_size=width,height;pixel_scale=1.,1.;
        time=0.;dt=1./.60.;fps=60.;count=0;mouse=0,0;mouse_delta=0,0;keys=[];
        mouse_buttons=[];events=[]}in
      Pxui.Ui.frame ui frame(fun ui->Pxui.Ui.panel ui~x:348.~y:16.~width:276.
        ~row_height:29~padding:8~max_height:448."r10"(fun()->
          for index=0 to 3 do
            ignore(Pxui.Ui.accordion ui~expanded:true("Section "^string_of_int(index+1))
              (fun()->Pxui.Ui.scope ui(string_of_int index)(fun()->
                ignore(Pxui.Ui.toggle ui"Enabled"(index land 1=0));
                ignore(Pxui.Ui.slider ui"Amount"~range:(-1.,1.)(float index/.4.));
                ignore(Pxui.Ui.int_slider ui"Steps"~range:(1,64)(8+index));
                ignore(Pxui.Ui.choice ui"Mode"["Solid";"Wire";"Points"](index mod 3)))))
          done));
      Ok{execution;scenario;descriptor;frame=0;image=None;canvas=None;
        setup_canvas_stats=None;ui=Some ui}
  |Scene3->ignore(Prismel_next_execution.destroy execution);Error"Scene3 uses its canonical interpreter"
let basic_scene value width height=Scene.[clear(Color.hex_exn"#07111f");rounded_rect~at:(18,18)~w:(width-36)~h:(height-36)~radius:18~fill:(Color.hex_exn"#111827")~stroke:(Color.hex_exn"#475569")();circle~at:(120,150)~radius:72~fill:(Color.hex_exn"#0891b2")();rect~at:(220,74)~w:180~h:120~fill:(Color.rgba 244 63 94 190)();translate 338 292[rotate(float value.frame*.0.01)[polygon[-80,-42;76,-54;98,36;0,74;-88,34]~fill:(Color.hex_exn"#a78bfa")~stroke:Color.white()]];image(Option.get value.image)~at:(470,92)~scale:1.15~angle:(-0.18)~center:(48,48)();bezier[34,404;176,320;282,474;430,382]~steps:48~color:(Color.hex_exn"#fbbf24")();text~at:(32,38)~size:18"Prismel renderer baseline";debug_text~at:(472,430)"FIXED 8x8"]
let canvas_scene value _width _height=
  Scene.[clear Color.black;image(Option.get value.image)~at:(0,0)()]
let update_canvas value ~width ~height =
  let phase=R10_scene2_legacy_equivalent.phase~frame:value.frame in
  let canvas=Option.get value.canvas in
  Canvas.render canvas Scene.[
    clear(Color.hex_exn"#07111f");
    rect~at:(0,0)~w:width~h:height~fill:(Color.hex_exn"#0f172a")();
    circle~at:(40+((phase*3)mod max 1(width-80)),height/2)
      ~radius:34~fill:(Color.hex_exn"#22d3ee")();
    translate(width/2)(height/2)[rotate(float phase*.0.02)[
      rounded_rect~at:(-90,-28)~w:180~h:56~radius:14
        ~fill:(Color.rgba 244 63 94 210)~stroke:Color.white()]];
    debug_text~at:(16,16)"CANVAS BASELINE"];
  match value.image with
  |Some image->
      (match Canvas.Private.copy_to_image canvas image with
       |Ok()->()
       |Error message->failwith message)
  |None->value.image<-Some(Result.get_ok(Canvas.to_image canvas))
let pxui_scene value=Scene.[clear(Color.hex_exn"#07111f");text~at:(24,24)~size:20"PXUI render baseline";rounded_rect~at:(18,62)~w:306~h:382~radius:12~fill:(Color.hex_exn"#111827")~stroke:(Color.hex_exn"#334155")();circle~at:(168,236)~radius:94~fill:(Color.hex_exn"#155e75")();debug_text~at:(88,420)"GRAPH / INSPECTOR"]@Pxui.Ui.scene(Option.get value.ui)
let render value ~width ~height =value.frame<-value.frame+1;
  if value.scenario=Canvas then update_canvas value~width~height;
  let scene=match value.scenario with Basic->basic_scene value width height|Canvas->canvas_scene value width height|Pxui->pxui_scene value|Scene3->assert false in
  submit_scene value.execution~width~height scene
let render_canonical value ~width ~height =
  value.frame <- 0;
  render value ~width ~height
let capture value=execution_ok(Prismel_next_execution.capture value.execution)
let stats value=execution_ok(Prismel_next_execution.stats value.execution)
let canvas_stats value=Option.map Canvas.Private.native_stats value.canvas
let presentation_facts value=
  execution_ok(Prismel_next_execution.presentation_facts value.execution)
let destroy value=Option.iter Image.destroy value.image;
  Option.iter Pxui.Ui.destroy value.ui;
  Option.iter Canvas.destroy value.canvas;
  execution_ok(Prismel_next_execution.destroy value.execution)
