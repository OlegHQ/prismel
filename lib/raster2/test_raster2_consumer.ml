open Raster2

let ok = function Ok value -> value | Error _ -> failwith "consumer error"
let rect x y width height = { Render_ir.x=x; y; width; height }

let commands frame width height =
  ok (Render_ir.create
    [| Clear 0x000000ffl;
       Push_clip (rect 0. 0. (float width) (float height));
       Geometry { vertices=[|0.;0.; float (width - 1);0.; 0.;float (height - 1)|];
                  indices=[|0;1;2|]; color=Int32.of_int (((frame land 255) lsl 24) lor 0xffff) };
       Image { resource_id=1; source=rect 0. 0. 2. 2.; destination=rect 1. 1. 2. 2. };
       Glyphs { resource_id=2; color=0xffffffffl; glyphs=[|{glyph_id=0;x=float(width-2);y=float(height-2)}|] };
       Pop_clip |])

let render frame width height =
  let target = ok (Surface.create ~width ~height ()) in
  let image = ok (Surface.create ~width:2 ~height:2 ()) in
  let depth_attachment = ok (Depth_stencil.create ~width ~height ()) in
  Surface.clear image 0x00ff00ffl;
  let atlas = { Consumer.width=1; height=1; pitch=1; bytes=Bytes.make 1 '\255'; cell_width=1; cell_height=1 } in
  let lookup = function 1 -> Some (Consumer.Image image) | 2 -> Some (Glyph_atlas atlas) | _ -> None in
  let depth = { Consumer.attachment=depth_attachment;
    state={Depth_stencil.depth_compare=Less;depth_write=true;stencil=None};
    value=0.5;clear=1.;clear_stencil=0 } in
  ok (Consumer.execute ~depth ~lookup ~target (commands frame width height));
  Bytes.cat (Surface.bytes target) (Depth_stencil.bytes depth_attachment)

let () =
  List.iter
    (fun frame ->
      let expected = render frame 8 6 in
      let workers = Array.init 4 (fun _ -> Domain.spawn (fun () -> render frame 8 6)) in
      Array.iter (fun worker -> assert (Domain.join worker = expected)) workers)
    [1;2;60;600];
  assert (Bytes.length (render 601 11 7) = 11 * 7 * 12);
  let target = ok (Surface.create ~width:2 ~height:2 ()) in
  Surface.clear target 0x12345678l;
  let before = Bytes.copy (Surface.bytes target) in
  let missing = ok (Render_ir.create [|Image {resource_id=99;source=rect 0. 0. 1. 1.;destination=rect 0. 0. 1. 1.}|]) in
  (match Consumer.execute ~lookup:(fun _ -> None) ~target missing with
  | Error (Consumer.Missing_resource 99) -> () | _ -> failwith "missing resource accepted");
  assert (Surface.bytes target = before);
  let rectangle indices = ok (Render_ir.create [|
    Clear 0x010203ffl;
    Geometry {vertices=[|0.;0.;640.;0.;640.;480.;0.;480.|];indices;
      color=0x19324bffl}|])in
  let fast_target=ok(Surface.create~width:640~height:480())
  and fallback_target=ok(Surface.create~width:640~height:480())in
  let fast=rectangle[|0;1;2;0;2;3|]
  and fallback=rectangle[|0;1;3;1;2;3|]in
  ok(Consumer.execute~lookup:(fun _->None)~target:fast_target fast);
  ok(Consumer.execute~lookup:(fun _->None)~target:fallback_target fallback);
  if Surface.bytes fast_target<>Surface.bytes fallback_target then
    failwith"rectangle fast path pixel drift";
  Gc.compact();
  let rectangle_before=Gc.allocated_bytes()in
  ok(Consumer.execute~lookup:(fun _->None)~target:fast_target fast);
  let rectangle_allocation=Gc.allocated_bytes()-.rectangle_before in
  if rectangle_allocation>1_300_000. then
    failwith(Printf.sprintf"rectangle fast path allocation %.0f"rectangle_allocation);
  let shared_vertices = Array.init 160 (fun index ->
    let vertex = index / 2 in
    if index land 1 = 0 then float (vertex mod 8) else float (vertex / 8)) in
  let shared_indices = Array.init (63 * 6) (fun index ->
    let cell = index / 6 and corner = index mod 6 in
    let x = cell mod 7 and y = cell / 7 and row = 8 in
    match corner with 0 -> y*row+x | 1 -> y*row+x+1 | 2 -> (y+1)*row+x+1
      | 3 -> y*row+x | 4 -> (y+1)*row+x+1 | _ -> (y+1)*row+x) in
  let shared = ok (Render_ir.create [|Geometry {
    vertices=shared_vertices; indices=shared_indices; color=0xabcdef80l }|]) in
  let allocation_target = ok (Surface.create ~width:8 ~height:9 ()) in
  for _ = 1 to 10 do ok (Consumer.execute ~lookup:(fun _ -> None) ~target:allocation_target shared) done;
  Gc.compact ();
  let allocated_before = Gc.allocated_bytes () in
  for _ = 1 to 100 do ok (Consumer.execute ~lookup:(fun _ -> None) ~target:allocation_target shared) done;
  let allocated_per_render = (Gc.allocated_bytes () -. allocated_before) /. 100. in
  if allocated_per_render >= 100_000. then
    failwith (Printf.sprintf "shared geometry allocation %.0f bytes/render" allocated_per_render);
  Printf.printf "Raster2 Consumer shared-geometry allocation: %.0f bytes/render\n"
    allocated_per_render;
  print_endline "Raster2 deterministic render IR consumer passed"
