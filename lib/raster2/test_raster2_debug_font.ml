open Raster2

let ok = function Ok value -> value | Error _ -> failwith "unexpected error"
let pixel surface x y = ok (Surface.get_rgba surface ~x ~y)

let render () =
  let surface = ok (Surface.create ~width:40 ~height:24 ()) in
  Surface.clear surface 0x102030ffl;
  let rect x y width height = { Render_ir.x; y; width; height } in
  let transform =
    { Render_ir.xx=0.; xy=(-2.); yx=2.; yy=0.; tx=20.; ty=10. }
  in
  let ir = ok (Render_ir.create
    [| Render_ir.Set_blend Composite.Source_over;
       Push_clip (rect 15. 12. 6. 5.);
       Push_transform transform;
       Debug_text { x=1.; y=2.; text="A\000ignored"; color=0xff000080l };
       Pop_transform;
       Pop_clip |])
  in
  ok (Consumer.execute ~lookup:(fun _ -> None) ~target:surface ir);
  surface, ir

let () =
  (* Exact SDL2_gfx 1.0.4 glyph rows, MSB first. *)
  assert (Array.init 8 (Debug_font.glyph_row 'A') =
    [|0x38;0x6c;0xc6;0xfe;0xc6;0xc6;0xc6;0x00|]);
  assert (Debug_font.width = 8 && Debug_font.height = 8);
  let surface, ir = render () in
  (* The affine transform moves only the anchor to (16,12). The diagnostic
     bitmap remains axis-aligned and one pixel per bitmap bit. *)
  let background = 0x102030ffl in
  let foreground = Composite.color ~blend:Source_over
      ~source:0xff000080l ~destination:background in
  assert (pixel surface 18 12 = foreground);
  assert (pixel surface 17 12 = background);
  (* Current clip truncates the A at x=21 and y=17. *)
  assert (pixel surface 20 13 = foreground);
  assert (pixel surface 21 13 = background);
  assert (pixel surface 18 17 = background);
  (* NUL compatibility prevents the following glyph from being drawn. *)
  assert (pixel surface 24 12 = background);
  let encoded = Render_ir.serialize ir and digest = Render_ir.hash ir in
  let workers = Array.init 4 (fun _ -> Domain.spawn (fun () ->
    let _, candidate = render () in
    Render_ir.serialize candidate, Render_ir.hash candidate)) in
  Array.iter (fun worker ->
    let candidate, candidate_digest = Domain.join worker in
    assert (candidate = encoded && candidate_digest = digest)) workers;
  let batched = ok (Render_ir.create
    [| Debug_text {x=0.;y=0.;text="A";color=0xffffffffl};
       Debug_text {x=8.;y=0.;text="B";color=0xffffffffl} |]) in
  (match Render_ir.batches batched with
  | [|{kind=Debug_text_batch 0xffffffffl;count=2;first=0}|] -> ()
  | _ -> failwith "debug text batching changed");
  (match Render_ir.create
    [|Debug_text {x=nan;y=0.;text="A";color=0l}|] with
  | Error Render_ir.Non_finite -> ()
  | _ -> failwith "non-finite debug anchor accepted");
  (match Render_ir.create
    [|Debug_text {x=0.;y=0.;text=String.make
        (Debug_font.max_text_length + 1) 'A';color=0l}|] with
  | Error Render_ir.Invalid_debug_text -> ()
  | _ -> failwith "oversized debug text accepted");
  (* Direct drawing is bounded and clips negative coordinates. *)
  let tiny = ok (Surface.create ~width:2 ~height:2 ()) in
  Surface.clear tiny 0x000000ffl;
  ok (Debug_font.draw ~target:tiny ~blend:Composite.Copy ~x:(-2) ~y:(-1)
    ~color:0xffffffffl "A");
  assert (pixel tiny 0 0 = 0xffffffffl);
  print_endline "Raster2 fixed SDL2_gfx debug font passed"
