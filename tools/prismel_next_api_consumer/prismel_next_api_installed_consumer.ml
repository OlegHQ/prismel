open Prismel_next_api

let require condition message = if not condition then failwith message

let read_file filename =
  let input = open_in_bin filename in
  Fun.protect ~finally:(fun () -> close_in input) (fun () ->
    really_input_string input (in_channel_length input))

let contains text fragment =
  let text_length = String.length text and fragment_length = String.length fragment in
  let rec loop offset =
    offset + fragment_length <= text_length
    && (String.sub text offset fragment_length = fragment || loop (offset + 1))
  in
  loop 0

let check_dependencies filename =
  let resolved = read_file filename in
  let public_modules =
    [ "Assets"; "Audio"; "Camera"; "Canvas"; "Color"; "Compute3";
      "Easy_camera"; "Easy_camera2"; "Event"; "Fog3"; "Font"; "Frame";
      "Image"; "Input"; "Light"; "Mat3"; "Mat4";
      "Material"; "Math"; "Mesh"; "Node3"; "Noise"; "Parallel"; "Path";
      "Preview"; "Quat"; "Rand"; "Scene"; "Scene3";
      "Shader3"; "Shadow3"; "Sketch"; "Texture"; "Time";
      "Transform_feedback3"; "Vec2"; "Vec3" ]
  in
  require (List.length public_modules = 37) "public module manifest cardinality";
  List.iter
    (fun name ->
      require
        (contains resolved ("Name: Prismel_next_api__" ^ name ^ "\n"))
        ("installed facade module missing: " ^ name))
    public_modules;
  require (contains resolved "Name: Prismel_next_api__Low\n")
    "installed Low facade missing";
  List.iter
    (fun required ->
      require (contains resolved required)
        ("missing resolved dependency: " ^ required))
    [ "Prismel_next_resources"; "Runtime_next_input" ];
  List.iter
    (fun forbidden ->
      require (not (contains resolved forbidden))
        ("legacy dependency escaped into installed consumer: " ^ forbidden))
    [ "Name: Prismel\n"; "Name: Runtime\n"; "Name: Tsdl\n";
      "Name: Tsdl_gfx\n"; "libSDL2" ]

let representative_values () =
  let v2 = Vec2.create 3. 4. and v3 = Vec3.create 1. 2. 3. in
  require (Vec2.length v2 = 5.) "Vec2";
  require (Vec3.dot v3 v3 = 14.) "Vec3";
  require (Color.hex "#ff0000" = Ok Color.red) "Color";
  require (Math.clamp 2. ~min:0. ~max:1. = 1.) "Math";
  ignore (Mat3.identity, Mat4.identity, Quat.identity);
  ignore (Rand.float (Rand.seed 7));
  ignore (Noise.sample2 (Noise.create 7) ~x:0.25 ~y:0.5);
  ignore (Fog3.linear ~start:1. ~end_:10. ~color:(Color.gray 128));
  let light = Light.directional ~direction:(Vec3.neg Vec3.unit_z) () in
  ignore (Material.create ~diffuse:Color.white ());
  ignore (Node3.create ());
  ignore Path.empty;
  require (Parallel.map succ [ 1; 2; 3 ] = [ 2; 3; 4 ]) "Parallel";
  let texture = Texture.create_exn ~width:1 ~height:1 [ Color.white ] in
  ignore (Texture.sample texture ~u:0. ~v:0.);
  let shader =
    Shader3.create ~vertex:Shader3.default_vertex
      ~fragment:Shader3.default_fragment ()
  in
  ignore
    (Compute3.dispatch ~groups:(1, 1, 1) ~local_size:(1, 1, 1)
       (fun _ -> ()));
  ignore (Input.mouse_pos, Event.WindowClosed, Frame.key_down, Time.now);
  ignore (Image.destroy, Canvas.destroy, Font.destroy, Audio.is_initialized,
          Assets.destroy);
  let mesh = Mesh.plane ~width:1. ~height:1. () in
  let camera =
    Camera.orthographic ~height:2. ~at:(Vec3.create 0. 0. 2.)
      ~target:Vec3.zero ()
  in
  ignore (Easy_camera.create ());
  ignore (Easy_camera2.create ());
  let feedback =
    Transform_feedback3.capture ~viewport:(0, 0, 8, 8) ~camera ~shader mesh
  in
  require (Transform_feedback3.primitive_count feedback = 2)
    "Transform_feedback3";
  let shadow =
    Shadow3.create ~light ~camera ~width:1 ~height:1 ~depths:[| 1. |] ()
  in
  require (Shadow3.size shadow = (1, 1)) "Shadow3";
  let scene = Scene3.create [ Scene3.mesh mesh ] in
  ignore (Scene.view3d ~camera scene);
  let scene2 = [ Scene.clear Color.black;
    Scene.rect ~at:(1, 1) ~w:4 ~h:4 ~fill:Color.red () ] in
  ignore (Result.get_ok (Scene.Private.to_ir scene2));
  Preview.start ~width:8 ~height:8 ();
  Preview.show scene2;
  require (Preview.is_open ()) "Preview";
  Preview.stop ();
  let sketch_config =
    { Sketch.default_config with width=8; height=8; clock=Fixed (1. /. 60.) }
  in
  let model =
    Sketch.run_state ~config:sketch_config ~init:(fun _ -> 0)
      ~update:(fun value _ -> value + 1)
      ~view:(fun _ _ -> scene2) ()
  in
  require (model = 1) "Sketch frame";
  let low_window =
    Result.get_ok
      (Low.Backend.start ~width:8 ~height:8 ~title:"consumer-low"
         ~resizable:false)
  in
  Low.Graphics.init low_window;
  Low.Graphics.clear Color.black;
  Low.Graphics.point ~x:2 ~y:2 ~color:Color.white ();
  Result.get_ok
    (Low.Backend.present low_window ~logical_width:8 ~logical_height:8);
  require (Low.Window.exists ()) "Low installed session";
  Low.Backend.stop ();
  require (not (Low.Window.exists ())) "Low installed teardown"

let () =
  if Array.length Sys.argv <> 2 then failwith "expected resolved dependency file";
  check_dependencies Sys.argv.(1);
  representative_values ();
  print_endline "Prismel next API installed consumer passed"
