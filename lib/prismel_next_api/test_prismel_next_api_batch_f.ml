open Prismel_next_api

let require condition message = if not condition then failwith message

let camera =
  Camera.orthographic ~height:2. ~near:0.1 ~far:10.
    ~at:(Vec3.create 0. 0. 2.) ~target:Vec3.zero ()

let triangle =
  Mesh.create_exn ~mode:Mesh.Triangles ~indices:[ 0; 1; 2 ]
    ~normals:[ Vec3.unit_z; Vec3.unit_z; Vec3.unit_z ]
    ~colors:[ Color.red; Color.green; Color.blue ]
    [ Vec3.create (-0.75) (-0.75) 0.; Vec3.create 0.75 (-0.75) 0.;
      Vec3.create 0. 0.75 0. ]

let scene samples =
  Scene3.create ~samples ~ambient:Color.white [ Scene3.mesh ~cull:Cull_none triangle ]

let snapshot samples =
  let target = Framebuffer3.render ~width:16 ~height:16 ~camera (scene samples) in
  (Texture.pixels (Framebuffer3.color target), Framebuffer3.depths target,
   Framebuffer3.stencils target)

let test_state () =
  let depth = Scene3.depth_state ~comparison:Greater_equal ~write:false ()
  and stencil =
    Scene3.stencil_state ~comparison:Equal ~reference:7 ~read_mask:0x0f
      ~write_mask:0xf0 ~on_stencil_fail:Replace ~on_depth_fail:Increment
      ~on_pass:Invert ()
  and raster = Scene3.raster_state ~line_width:2. ~point_size:3. () in
  let value =
    Scene3.create ~depth_clear:0.25 ~stencil_clear:9 ~samples:4
      [ Scene3.with_depth depth
          [ Scene3.with_stencil stencil
              [ Scene3.with_raster raster [ Scene3.mesh triangle ] ] ] ]
  in
  match Scene3.Private.drawings value with
  | [ drawing ] ->
      require (drawing.depth = depth) "depth state drift";
      require (drawing.stencil = stencil) "stencil state drift";
      require (drawing.raster = raster) "raster state drift";
      require (Scene3.Private.samples value = 4) "sample state drift"
  | _ -> failwith "unexpected Scene3 drawing count"

let test_feedback () =
  let shader =
    Shader3.create ~vertex:Shader3.default_vertex
      ~fragment:Shader3.default_fragment ()
  in
  let feedback =
    Transform_feedback3.capture ~viewport:(0, 0, 16, 16) ~camera ~shader
      triangle
  in
  require (Transform_feedback3.primitive_count feedback = 1)
    "transform feedback primitive count";
  require (Transform_feedback3.vertex_count feedback = 3)
    "transform feedback vertex count"

let test_frames () =
  List.iter
    (fun samples ->
      let expected = snapshot samples in
      List.iter
        (fun frame ->
          let actual = snapshot samples in
          require (actual = expected)
            (Printf.sprintf "Framebuffer3 drift at frame %d/sample %d" frame
               samples))
        [ 1; 2; 60; 600 ])
    [ 1; 4; 9; 16 ]

let test_shadow () =
  let light = Light.directional ~direction:(Vec3.create 0. 0. (-1.)) () in
  let target = Framebuffer3.render ~width:8 ~height:8 ~camera (scene 1) in
  let shadow = Framebuffer3.shadow ~filter:Shadow3.Pcf_3x3 ~light ~camera target in
  require (Shadow3.size shadow = (8, 8)) "shadow attachment size";
  require (Shadow3.light shadow = light) "shadow light identity";
  match Framebuffer3.to_canvas target with
  | Error message -> failwith message
  | Ok canvas -> Canvas.destroy canvas

let () =
  test_state ();
  test_feedback ();
  test_frames ();
  test_shadow ();
  print_endline "Prismel next API Batch F tests passed"
