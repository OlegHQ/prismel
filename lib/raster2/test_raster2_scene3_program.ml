open Raster2

let get = function Ok value -> value | Error _ -> failwith "program render"

let vertex x y color varying : Scene3_program.vertex =
  { clip_x = x; clip_y = y; clip_z = 0.5; clip_w = 1.;
    world = { x; y; z = 0. }; normal = { x = 0.; y = 0.; z = 1. }; color;
    tex_coord = { x = (x +. 1.) *. 0.5; y = (y +. 1.) *. 0.5 };
    varyings = [| varying |] }

let primitive =
  Scene3_program.Triangle
    (vertex (-1.) (-1.) 0xff0000ffl 0., vertex 3. (-1.) 0x00ff00ffl 1.,
     vertex (-1.) 3. 0x0000ffffl 0.5)

let render frame =
  let color = get (Surface.create ~width:8 ~height:8 ()) in
  let depth = get (Depth_stencil.create ~width:8 ~height:8 ()) in
  Surface.clear color 0x010203ffl;
  ignore (Depth_stencil.clear depth ~depth:1. ~stencil:0);
  let fragment (input : Scene3_program.fragment_input) =
    if input.screen.x > 6. then None
    else Some { Scene3_program.color =
                  (if input.varyings.(0) > 0.5 then 0xffffffffl else input.color);
                depth = Some (if frame land 1 = 0 then 0.25 else input.depth) }
  in
  get (Scene3_program.render ~color ~depth:(Some depth)
         ~depth_state:{ depth_compare = Depth_stencil.Always; depth_write = true;
                        stencil = None }
         ~blend:Composite.Copy ~cull:Triangle.Cull_none
         ~clip:{ x = 0; y = 0; width = 8; height = 8 }
         ~point_size:1. ~line_width:1. ~varying_count:1 ~fragment [| primitive |]);
  Bytes.copy (Surface.bytes color), Bytes.copy (Depth_stencil.bytes depth)

let () =
  let odd = render 1 and even = render 2 in
  if odd = even then failwith "program depth override ignored";
  let workers = Array.init 4 (fun _ ->
      Domain.spawn (fun () -> Array.init 600 (fun i -> render (i + 1)))) in
  let expected = Array.init 600 (fun i -> render (i + 1)) in
  Array.iter (fun worker ->
      if Domain.join worker <> expected then failwith "program domain drift") workers;
  let color = get (Surface.create ~width:2 ~height:2 ()) in
  Surface.clear color 0x11223344l;
  let before = Bytes.copy (Surface.bytes color) in
  let malformed_vertex = { (vertex 0. 1. 0l 0.) with varyings = [||] } in
  let malformed = Scene3_program.Triangle
      (vertex (-1.) (-1.) 0l 0., vertex 1. (-1.) 0l 0., malformed_vertex) in
  (match Scene3_program.render ~color ~depth:None
           ~depth_state:{ depth_compare = Depth_stencil.Always; depth_write = false;
                          stencil = None }
           ~blend:Composite.Copy ~cull:Triangle.Cull_none
           ~clip:{ x = 0; y = 0; width = 2; height = 2 }
           ~point_size:1. ~line_width:1. ~varying_count:1 ~fragment:(fun _ -> None)
           [| malformed |] with
   | Error Scene3_program.Varying_cardinality -> ()
   | _ -> failwith "varying rejection");
  if Surface.bytes color <> before then failwith "program rejection mutated target";
  print_endline
    "Raster2 programmable triangle: varyings/discard/depth/atomic/4-domain passed"
