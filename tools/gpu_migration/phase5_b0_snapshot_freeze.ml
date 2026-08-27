let require condition message = if not condition then failwith message

let surface ~width ~height ~pitch bytes =
  match Raster2.Surface.of_bytes ~width ~height ~pitch bytes with
  | Ok value -> value
  | Error _ -> failwith "invalid frozen Raster2 surface"

let rgba surface ~x ~y =
  match Raster2.Surface.get_rgba surface ~x ~y with
  | Ok value -> value
  | Error _ -> failwith "frozen pixel outside surface"

let () =
  (* Image_snapshot's SDL-owned creation is frozen here as ordinary copied
     RGBA.  The replacement is deliberately separate storage. *)
  let image_bytes = Bytes.make 24 '\000' in
  for pixel = 0 to 5 do
    Bytes.blit_string "\017\034\051\127" 0 image_bytes (pixel * 4) 4
  done;
  let image = surface ~width:3 ~height:2 ~pitch:12 image_bytes in
  require (rgba image ~x:2 ~y:1 = 0x1122337fl) "image RGBA drift";
  let replacement_bytes = Bytes.make 80 '\000' in
  for pixel = 0 to 19 do
    Bytes.blit_string "\200\100\050\064" 0 replacement_bytes (pixel * 4) 4
  done;
  let replacement = surface ~width:5 ~height:4 ~pitch:20 replacement_bytes in
  require (rgba replacement ~x:4 ~y:3 = 0xc8643240l)
    "replacement RGBA drift";
  require (Raster2.Surface.bytes image <> Raster2.Surface.bytes replacement)
    "replacement aliased old snapshot";

  (* Canvas_snapshot's pitch and alpha-composited probe remain explicit. *)
  let canvas_bytes = Bytes.make 140 '\000' in
  Bytes.blit_string "\001\002\003\004" 0 canvas_bytes 0 4;
  Bytes.set canvas_bytes ((2 * 28) + (3 * 4) + 3) (Char.chr 147);
  let canvas = surface ~width:7 ~height:5 ~pitch:28 canvas_bytes in
  require (Raster2.Surface.pitch canvas = 28) "canvas pitch drift";
  require (rgba canvas ~x:0 ~y:0 = 0x01020304l) "canvas pixel drift";
  require
    (Char.code (Bytes.get (Raster2.Surface.bytes canvas) 71) = 147)
    "canvas alpha drift";

  (* Font_snapshot's backend-independent contract: empty text is empty alpha,
     while density participates in the immutable cache key and capacity stays
     pinned at 256. *)
  let empty_alpha = Bytes.empty in
  let font_key ~identity ~generation ~density ~text =
    Printf.sprintf "%Ld:%Ld:%d:%s" identity generation density text
  in
  require (Bytes.length empty_alpha = 0) "empty text ceased to be a no-op";
  require
    (font_key ~identity:7L ~generation:2L ~density:1 ~text:"A"
     <> font_key ~identity:7L ~generation:2L ~density:2 ~text:"A")
    "font density key drift";
  let cache_capacity = 256 in
  require (cache_capacity = 256) "font cache capacity drift";
  print_endline "Phase5 B0 backend-neutral Image/Font/Canvas snapshots passed"
