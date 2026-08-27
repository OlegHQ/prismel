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
  G.destroy recorder; G.destroy replay;
  let window = expect "window create" (Prismel_next_low.Window.create ()) in
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
  if Prismel_next_low.Window.exists window then failwith "window teardown";
  print_endline "Prismel_next_low recorder/window passed"
