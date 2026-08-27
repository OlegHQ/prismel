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
  let recorder = ok (G.create ~capacity:32 ()) in
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
  let first = ok (G.flush recorder) in
  let frozen = Raster2.Render_ir.serialize first in
  for _ = 1 to 100_000 do
    ok (G.point recorder ~x:1 ~y:2 ());
    let value = ok (G.flush recorder) in
    if Array.length (Raster2.Render_ir.commands value) <> 1 then
      failwith "flush cardinality"
  done;
  if G.command_count recorder <> 0 || G.peak_commands recorder > 32 then
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
  if Raster2.Render_ir.serialize (ok (G.flush replay)) <> frozen then
    failwith "recorder drift";
  G.destroy recorder; G.destroy replay;
  let window = expect "window create" (Prismel_next_low.Window.create ()) in
  expect "window resize" (Prismel_next_low.Window.set_size window 17 13);
  if Prismel_next_low.Window.size window <> (17,13) then failwith "resize";
  expect "window destroy" (Prismel_next_low.Window.destroy window);
  if Prismel_next_low.Window.exists window then failwith "window teardown";
  print_endline "Prismel_next_low recorder/window passed"
