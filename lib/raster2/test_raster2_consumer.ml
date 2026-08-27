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
  print_endline "Raster2 deterministic render IR consumer passed"
