open Prismel_next_api

let require condition format =
  Printf.ksprintf (fun message -> if not condition then failwith message) format

let read path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
    really_input_string channel (in_channel_length channel))

let contains text needle =
  let rec loop offset =
    offset + String.length needle <= String.length text
    && (String.sub text offset (String.length needle) = needle
        || loop (offset + 1))
  in
  loop 0

let count text needle =
  let rec loop offset total =
    if offset + String.length needle > String.length text then total
    else if String.sub text offset (String.length needle) = needle then
      loop (offset + String.length needle) (total + 1)
    else loop (offset + 1) total
  in
  loop 0 0

let hash_bytes bytes =
  let value = ref 0xcbf29ce484222325L in
  Bytes.iter
    (fun byte ->
      value := Int64.logxor !value (Int64.of_int (Char.code byte));
      value := Int64.mul !value 0x100000001b3L)
    bytes;
  !value

let hash value = Marshal.to_bytes value [ Marshal.No_sharing ] |> hash_bytes

let basic_scene frame =
  [ Scene.clear (Color.rgb 12 18 28);
    Scene.circle ~at:(8 + (frame mod 3), 8) ~radius:5 ~fill:Color.red ();
    Scene.rect ~at:(frame mod 2, 13) ~w:16 ~h:2 ~fill:Color.white () ]

let pxui_like frame =
  [ Scene.clear (Color.rgb 24 26 32);
    Scene.rect ~at:(1, 1) ~w:14 ~h:14 ~fill:(Color.rgb 45 48 58)
      ~stroke:Color.white ();
    Scene.rect ~at:(3, 4) ~w:(5 + (frame mod 4)) ~h:3
      ~fill:(Color.rgb 60 150 230) ();
    Scene.circle ~at:(12, 11) ~radius:2 ~fill:(Color.rgb 245 180 40) () ]

let ir_hash scene = Scene.Private.to_ir scene |> Result.get_ok |> hash

let scene3_hash () =
  let mesh =
    Mesh.create_exn ~mode:Mesh.Triangles ~indices:[ 0; 1; 2 ]
      ~normals:[ Vec3.unit_z; Vec3.unit_z; Vec3.unit_z ]
      ~colors:[ Color.red; Color.green; Color.blue ]
      [ Vec3.create (-0.8) (-0.8) 0.; Vec3.create 0.8 (-0.8) 0.;
        Vec3.create 0. 0.8 0. ]
  and camera =
    Camera.orthographic ~height:2. ~at:(Vec3.create 0. 0. 2.)
      ~target:Vec3.zero ()
  in
  let target =
    Framebuffer3.render ~width:16 ~height:16 ~camera
      (Scene3.create ~samples:4 ~ambient:Color.white
         [ Scene3.mesh ~cull:Cull_none mesh ])
  in
  hash
    (Texture.pixels (Framebuffer3.color target), Framebuffer3.depths target,
     Framebuffer3.stencils target)

let resource_fixture () =
  let canvas = Canvas.create_exn ~width:4 ~height:4 in
  Canvas.clear canvas Color.black;
  Canvas.set_pixel canvas ~x:1 ~y:1 Color.red;
  let image = Canvas.to_image canvas |> Result.get_ok in
  let identity = Image.Private.identity image and generation = Image.Private.generation image in
  let scene = [ Scene.image image ~at:(2, 3) () ] in
  let expected = ir_hash scene in
  List.iter
    (fun frame ->
      require (ir_hash scene = expected) "resource IR drift at frame %d" frame;
      require (Image.Private.identity image = identity) "image identity drift";
      require (Image.Private.generation image = generation) "stable image generation drift")
    [ 1; 2; 60; 600 ];
  Image.destroy image;
  Canvas.destroy canvas;
  expected

let execute_target target =
  let frames = [ 1; 2; 60; 600 ] in
  let basic = List.map (fun frame -> frame, ir_hash (basic_scene frame)) frames
  and pxui = List.map (fun frame -> frame, ir_hash (pxui_like frame)) frames in
  Preview.start ~width:16 ~height:16 ~title:("facade-" ^ target) ();
  List.iter (fun frame -> Preview.show (basic_scene frame)) frames;
  Preview.stop ();
  require (not (Preview.is_open ())) "%s Preview teardown" target;
  let fixed = { Sketch.default_config with width=16; height=16;
    clock=Sketch.Fixed (1. /. 60.) } in
  let model = Sketch.run_state ~config:fixed ~init:(fun _ -> 0)
      ~update:(fun value _ -> value + 1)
      ~view:(fun value _ -> pxui_like value) () in
  require (model = 1) "%s Sketch finite default" target;
  basic, pxui

let check_scope root =
  let mapping = read (Filename.concat root
    "specification/evidence/gpu_migration/phase5_prismel_api_map.json") in
  require (count mapping "\"module\"" = 40) "API map is not exact 40";
  let low_omissions =
    [ "Prismel.Low.Graphics.get_renderer";
      "Prismel.Low.Window.get_window"; "Prismel.Low.Window.get_renderer";
      "Prismel.Low.Window.get_window_flags";
      "Prismel.Low.Window.get_renderer_flags";
      "Prismel.Low.Window.with_gpu_context"; "Prismel.Low.Window.t.window";
      "Prismel.Low.Window.t.renderer";
      "Prismel.Low.Window.t.renderer_context" ]
  in
  require (List.length low_omissions = 9) "Low omission cardinality";
  List.iter (fun omission -> require (contains mapping omission)
    "missing Low omission %s" omission) low_omissions;
  require (not (contains mapping "\"status\": \"raw_only\""))
    "high-level raw-only facade remains";
  let command = Printf.sprintf "git -C %s diff --quiet -- examples"
      (Filename.quote root) in
  require (Sys.command command = 0) "example source changes are in the worktree"

let () =
  let root = ref "." and target = ref "" in
  Arg.parse
    [ "--root", Arg.Set_string root, "repository root";
      "--target", Arg.Set_string target, "headless or web" ]
    (fun value -> raise (Arg.Bad value)) "phase5_final_facade";
  require (List.mem !target [ "headless"; "web" ]) "invalid target";
  check_scope !root;
  let basic, pxui = execute_target !target in
  let canvas = resource_fixture () and scene3 = scene3_hash () in
  let basic_hash = hash basic and pxui_hash = hash pxui in
  require (basic_hash = 0x535e25a21992b801L)
    "%s Basic hash drift: %016Lx" !target basic_hash;
  require (pxui_hash = 0x29ea844d81e890f0L)
    "%s PXUI-like hash drift: %016Lx" !target pxui_hash;
  require (canvas = 0x6cfaaeb1e2b33dc4L)
    "%s Canvas/resource hash drift: %016Lx" !target canvas;
  require (scene3 = 0xfe1df44e05ef82baL)
    "%s Scene3 hash drift: %016Lx" !target scene3;
  Printf.printf
    "Phase5 final facade %s: basic=%016Lx pxui=%016Lx canvas=%016Lx scene3=%016Lx\n"
    !target basic_hash pxui_hash canvas scene3
