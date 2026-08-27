open Raster2

let ok = function Ok value -> value | Error _ -> failwith "scene3 consumer"
let white = { Scene3_lighting.r = 1.; g = 1.; b = 1.; a = 1. }
let black = { Scene3_lighting.r = 0.; g = 0.; b = 0.; a = 1. }

let lighting =
  {
    Scene3_lighting.ambient = black;
    lights =
      [|
        Directional
          {
            direction = { x = 0.; y = 0.; z = -1. };
            color = white;
            intensity = 1.;
          };
      |];
    material =
      { ambient = black; diffuse = white; specular = black; emissive = black; shininess = 0. };
    fog = No_fog;
    separate_specular = false;
    two_sided = false;
  }

let matrix =
  [| 1.; 0.; 0.; 0.; 0.; 1.; 0.; 0.; 0.; 1.; 0.; 0.; 0.; 0.; 0.; 1. |]

let depth_stencil =
  { Depth_stencil.depth_compare = Less; depth_write = true; stencil = None }

let render ~topology ~indices ~cull mode ~line_width ~point_size =
  let color = ok (Surface.create ~width:16 ~height:12 ()) in
  let depth = ok (Depth_stencil.create ~width:16 ~height:12 ()) in
  let normal = { Scene3_lighting.x = 0.; y = 0.; z = 1. } in
  let vertex x y =
    {
      Scene3_consumer.position = { Scene3_lighting.x = x; y; z = 0.4 };
      normal;
      color = 0xffffffffl;
      u = x;
      v = y;
    }
  in
  let draw =
    {
      Scene3_consumer.matrix;
      viewport =
        { Scene3.x = 0.; y = 0.; width = 16.; height = 12.; min_depth = 0.; max_depth = 1. };
      scissor = { Triangle.x = 1; y = 1; width = 14; height = 10 };
      topology;
      vertices =
        [|
          vertex (-0.8) (-0.8);
          vertex 0.8 (-0.8);
          vertex (-0.8) 0.8;
          vertex 0.8 0.8;
        |];
      indices;
      lighting;
      shadows = [| None |];
      shading = Smooth;
      texture = None;
      cull;
      blend = Composite.Source_over;
      depth_stencil;
      mode;
      line_width;
      point_size;
    }
  in
  ok
    (Scene3_consumer.render
       ~target:{ color; depth = Some depth; multisample = None }
       ~clear:0x000000ffl ~clear_depth:1. ~clear_stencil:0 ~draws:[| draw |]);
  Bytes.cat (Surface.bytes color) (Depth_stencil.bytes depth)

let changed_pixels bytes =
  let count = ref 0 in
  for offset = 0 to (16 * 12) - 1 do
    if Bytes.get_int32_le bytes (offset * 4) <> 0xff000000l then incr count
  done;
  !count

let changed_depth bytes =
  let start = 16 * 12 * 4 in
  let changed = ref false in
  for offset = 0 to (16 * 12) - 1 do
    let bits = Bytes.get_int32_le bytes (start + (offset * 8)) in
    if Int32.float_of_bits bits < 1. then changed := true
  done;
  !changed

let cases =
  [
    (Scene3.Triangle_strip, [| 0; 1; 2; 3 |], [| 0; 1; 2; 2; 1; 3 |], "strip");
    (Scene3.Triangle_fan, [| 0; 1; 3; 2 |], [| 0; 1; 3; 0; 3; 2 |], "fan");
  ]

let render_case topology indices mode ~line_width ~point_size =
  render ~topology ~indices ~cull:Triangle.Cull_none mode ~line_width ~point_size

let test_case (topology, indices, expanded, name) =
  List.iter
    (fun mode ->
      let expected = render_case topology indices mode ~line_width:2. ~point_size:3. in
      for _frame = 1 to 600 do
        if render_case topology indices mode ~line_width:2. ~point_size:3. <> expected then
          failwith (name ^ " frame drift")
      done;
      let workers =
        Array.init 4 (fun _ ->
            Domain.spawn (fun () ->
                render_case topology indices mode ~line_width:2. ~point_size:3.))
      in
      Array.iter
        (fun worker ->
          if Domain.join worker <> expected then failwith (name ^ " domain drift"))
        workers)
    [ Scene3_consumer.Faces; Wireframe; Vertices ];
  List.iter
    (fun mode ->
      let source = render_case topology indices mode ~line_width:2. ~point_size:3. in
      let canonical =
        render_case Scene3.Triangle_list expanded mode ~line_width:2. ~point_size:3.
      in
      if source <> canonical then failwith (name ^ " canonical expansion/dedup drift"))
    [ Scene3_consumer.Wireframe; Vertices ];
  let wire1 = render_case topology indices Wireframe ~line_width:1. ~point_size:1. in
  let wire5 = render_case topology indices Wireframe ~line_width:5. ~point_size:1. in
  let point1 = render_case topology indices Vertices ~line_width:1. ~point_size:1. in
  let point5 = render_case topology indices Vertices ~line_width:1. ~point_size:5. in
  if changed_pixels wire5 <= changed_pixels wire1 then failwith (name ^ " wire width ignored");
  if changed_pixels point5 <= changed_pixels point1 then failwith (name ^ " point size ignored");
  if not (changed_depth wire1 && changed_depth point1) then
    failwith (name ^ " polygon depth state ignored");
  let front =
    render ~topology ~indices ~cull:Triangle.Front Wireframe ~line_width:1. ~point_size:1.
  in
  let back =
    render ~topology ~indices ~cull:Triangle.Back Wireframe ~line_width:1. ~point_size:1.
  in
  if front = back then failwith (name ^ " winding/cull state ignored")

let () =
  List.iter test_case cases;
  let target = ok (Surface.create ~width:2 ~height:2 ()) in
  let before = Bytes.copy (Surface.bytes target) in
  ok
    (Scene3_consumer.render
       ~target:{ color = target; depth = None; multisample = None }
       ~clear:0x01020304l ~clear_depth:1. ~clear_stencil:0 ~draws:[||]);
  if Surface.bytes target = before then failwith "empty clear missing";
  print_endline "Raster2 deterministic Scene3 strip/fan polygon modes passed"
