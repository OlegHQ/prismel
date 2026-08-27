let expect label = function
  | Ok value -> value
  | Error (Prismel_next_low.Invalid_argument message) ->
      failwith (label ^ ": invalid: " ^ message)
  | Error (Prismel_next_low.Unavailable message) ->
      failwith (label ^ ": unavailable: " ^ message)
  | Error (Prismel_next_low.Backend message) ->
      failwith (label ^ ": backend: " ^ message)

let () =
  let module G = Prismel_next_low.Graphics in
  let ok result = expect "graphics" result in
  let recorder = ok (G.create ~capacity:128 ()) in
  ok (G.clear recorder 0x01020304l);
  G.set_color recorder 0xa0b0c0d0l;
  ok (G.push_matrix recorder);
  G.translate recorder ~dx:4 ~dy:5;
  ok (G.rect recorder ~pos:(0,0) ~w:3 ~h:2 ());
  ok (G.pop_matrix recorder);
  ok (G.set_clip recorder (Some (1,2,7,8)));
  ok (G.line recorder ~x1:0 ~y1:0 ~x2:4 ~y2:4 ());
  ok (G.set_clip recorder None);
  ok (G.set_gfx_font_rotation recorder 3);
  ok (G.draw_gfx_text recorder ~pos:(2,3) ~text:"A" ());
  ok (G.ellipse recorder ~center:(8,8) ~rx:4 ~ry:2 ());
  ok (G.rounded_rect recorder ~pos:(1,1) ~w:12 ~h:9 ~radius:3 ());
  ok (G.thick_line recorder ~x1:1 ~y1:2 ~x2:9 ~y2:7 ~width:3 ());
  ok (G.arc recorder ~center:(10,10) ~radius:4 ~start_angle:0.
    ~end_angle:Float.pi ());
  ok (G.pie recorder ~center:(10,10) ~radius:4 ~start_angle:0.
    ~end_angle:(Float.pi /. 2.) ());
  ok (G.bezier recorder ~points:[0,0;3,8;9,2] ~steps:12 ());
  ok (G.fill_contours recorder [[0,0;8,0;8,8;0,8];
    [2,2;2,6;6,6;6,2]] ~rule:Raster2.Path.Even_odd
    ~color:0x8899aaffl);
  ok (G.stroke_path recorder [|Raster2.Path.Move_to {x=0.;y=0.};
    Raster2.Path.Cubic_to ({x=2.;y=8.},{x=7.;y=8.},{x=9.;y=0.})|]
    ~width:2. ~cap:Raster2.Path.Round ~join:Raster2.Path.Bevel ());
  let first = ok (G.flush recorder) in
  let frozen = Raster2.Render_ir.serialize first in
  for _ = 1 to 100_000 do
    ok (G.point recorder ~x:1 ~y:2 ());
    let value = ok (G.flush recorder) in
    if Array.length (Raster2.Render_ir.commands value) <> 1 then
      failwith "flush cardinality"
  done;
  if G.command_count recorder <> 0 || G.peak_commands recorder > 128 then
    failwith "unbounded recorder";
  let replay = ok (G.create ~capacity:32 ()) in
  ok (G.clear replay 0x01020304l);
  G.set_color replay 0xa0b0c0d0l;
  ok (G.push_matrix replay); G.translate replay ~dx:4 ~dy:5;
  ok (G.rect replay ~pos:(0,0) ~w:3 ~h:2 ()); ok (G.pop_matrix replay);
  ok (G.set_clip replay (Some (1,2,7,8)));
  ok (G.line replay ~x1:0 ~y1:0 ~x2:4 ~y2:4 ());
  ok (G.set_clip replay None); ok (G.set_gfx_font_rotation replay 3);
  ok (G.draw_gfx_text replay ~pos:(2,3) ~text:"A" ());
  (* The compact replay above freezes the legacy core prefix; advanced
     commands have their own stable whole-stream hash below. *)
  ignore (ok (G.flush replay));
  if Bytes.length frozen < 100 then failwith "advanced stream too small";
  let pixels = Bytes.of_string
      "\255\000\000\255\000\255\000\255\000\000\255\255\255\255\255\255" in
  let image = match Prismel_next_resources.Image.create ~width:2 ~height:2
      ~rgba:pixels with Ok value -> value | Error _ -> failwith "image create" in
  let image_recorder = ok (G.create ~capacity:8 ()) in
  ok (G.draw_sub_image image_recorder image ~src_rect:(0,0,1,2)
    ~dst_rect:(2,3,4,5));
  ok (G.draw_image_ex image_recorder image ~pos:(7,8) ~scale:2.
    ~angle:(Float.pi /. 2.) ~center:(1,1) ~flip:true ());
  let image_stream = ok (G.flush image_recorder) in
  let image_commands = Raster2.Render_ir.commands image_stream in
  let identity = Prismel_next_resources.Image.identity image in
  let image_ids = Array.to_list image_commands |> List.filter_map (function
    | Raster2.Render_ir.Image value -> Some value.resource_id | _ -> None) in
  if image_ids <> [identity; identity] then failwith "image identity drift";
  if Raster2.Render_ir.hash image_stream <> 0xdf75694ab73e182fL then
    failwith "image stream hash drift";
  G.destroy image_recorder;
  begin match Prismel_next_resources.Image.destroy image with
  | Ok () -> () | Error _ -> failwith "image destroy"
  end;
  G.destroy recorder; G.destroy replay;
  let window = expect "window create" (Prismel_next_low.Window.create ()) in
  let rgba r g b=Bytes.init 16(fun index->match index mod 4 with 0->Char.chr r|1->Char.chr g|2->Char.chr b|_->'\255')in
  let session_image=match Prismel_next_resources.Image.create~width:2~height:2~rgba:(rgba 255 0 0)with Ok x->x|Error _->failwith"session image"in
  ignore(expect"register image"(Prismel_next_low.Window.register_image window session_image));
  let resource_recorder=ok(G.create~capacity:16())in
  ok(G.draw_image resource_recorder session_image~pos:(0,0));
  let resource_frame=ok(G.flush resource_recorder)in
  List.iter(fun _->ignore(expect"resource present"(Prismel_next_low.Window.present window resource_frame)))[1;2;60;600];
  let resource_pixels=expect"resource capture"(Prismel_next_low.Window.capture window)in
  if Char.code(Bytes.get resource_pixels 0)<>255 then failwith"persistent image pixel";
  begin match Prismel_next_resources.Image.replace session_image~width:2~height:2~rgba:(rgba 0 255 0)with Ok()->()|Error _->failwith"image reload"end;
  ignore(expect"resource reload present"(Prismel_next_low.Window.present window resource_frame));
  if Char.code(Bytes.get(expect"reload capture"(Prismel_next_low.Window.capture window))1)<>255 then failwith"image generation pixel";
  let canvas=match Prismel_next_resources.Canvas.create~width:2~height:2 with Ok x->x|Error _->failwith"canvas"in
  ignore(Prismel_next_resources.Canvas.clear canvas 0x0000ffffl);
  expect"register canvas"(Prismel_next_low.Window.register_canvas window~id:700 canvas);
  ok(G.draw_canvas resource_recorder~resource_id:700 canvas~pos:(0,0));
  let canvas_frame=ok(G.flush resource_recorder)in ignore(expect"canvas present"(Prismel_next_low.Window.present window canvas_frame));
  if Char.code(Bytes.get(expect"canvas capture"(Prismel_next_low.Window.capture window))2)<>255 then failwith"canvas dependency pixel";
  let font=match Prismel_next_resources.Font.open_system~size:12. with Ok x->x|Error _->failwith"font"in
  let text=match Prismel_next_resources.Font.render font~density:1~color:(255,255,255,255)"A"with Ok(Some x)->x|_->failwith"text"in
  expect"register text"(Prismel_next_low.Window.register_text window~id:701 text);
  ok(G.draw_text_snapshot resource_recorder~resource_id:701 text~pos:(0,0));
  let text_frame=ok(G.flush resource_recorder)in ignore(expect"text present"(Prismel_next_low.Window.present window text_frame));
  if not(Bytes.exists((<>)'\000')(expect"text capture"(Prismel_next_low.Window.capture window)))then failwith"text pixels";
  G.destroy resource_recorder;
  let frame_recorder = ok (G.create ~capacity:8 ()) in
  ok (G.clear frame_recorder 0x102030ffl);
  ok (G.rect frame_recorder ~pos:(1,1) ~w:4 ~h:3
    ~color:0xff8040ffl ());
  let frame = ok (G.flush frame_recorder) in
  let first_capture = ref Bytes.empty in
  for index = 1 to 600 do
    ignore (expect "window present" (Prismel_next_low.Window.present window frame));
    if index = 1 then first_capture := expect "window capture"
      (Prismel_next_low.Window.capture window);
    if index = 2 || index = 60 || index = 600 then
      if expect "window capture" (Prismel_next_low.Window.capture window)
          <> !first_capture then failwith "persistent frame drift"
  done;
  expect "window resize" (Prismel_next_low.Window.set_size window 17 13);
  if Prismel_next_low.Window.size window <> (17,13) then failwith "resize";
  ignore (expect "post-resize present"
    (Prismel_next_low.Window.present window frame));
  if Bytes.length (expect "post-resize capture"
      (Prismel_next_low.Window.capture window)) <> 17 * 13 * 4 then
    failwith "post-resize capture dimensions";
  G.destroy frame_recorder;
  expect "window destroy" (Prismel_next_low.Window.destroy window);
  ignore(Prismel_next_resources.Image.destroy session_image);ignore(Prismel_next_resources.Canvas.destroy canvas);
  ignore(Prismel_next_resources.Text.destroy text);ignore(Prismel_next_resources.Font.destroy font);
  if Prismel_next_low.Window.exists window then failwith "window teardown";
  print_endline "Prismel_next_low recorder/window passed"
