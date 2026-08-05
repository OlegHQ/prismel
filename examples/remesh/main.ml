open Prismel
open Procedural

type model = {
  session : Session.t;
  input : Mesh.t;
  remeshed : Mesh.t;
  camera : Easy_camera.t;
  frames_left : int option;
}

let cook session frame graph =
  let context = Context.of_frame ~seed:2026L frame |> Result.get_ok in
  match Bridge.cook_to_mesh session ~context graph with
  | Ok (mesh, _warnings) -> mesh
  | Error error -> failwith (Diagnostic.error_to_string error)

let source () =
  Sop.uv_sphere ~connectivity:Pdk.Ops.Sphere_alternating_triangles
    ~normals:Pdk.Ops.Sphere_point_normals ~segments:18 ~rings:9
    ~radius_x:1.25 ~radius_y:0.82 ~radius_z:0.72 ~radius:1. ()
  |> Sop.mountain ~seed:91 ~height:0.12
       ~frequency:(Vec3.create 2.2 1.7 2.5) ~octaves:4
       ~recompute_normals:true

let init frame =
  let session = Session.create ~max_entries:8
      ~max_payload_bytes:(64 * 1024 * 1024) |> Result.get_ok in
  let input_graph = source () in
  let remeshed_graph = input_graph
    |> Sop.remesh ~target_length:0.18 ~iterations:3 ~smoothing:0.35
         ~project:true ~preserve_uv_seams:false
         ~output_hard_edges:"hard_edges" ~output_quality:"quality" in
  {
    session;
    input = cook session frame input_graph;
    remeshed = cook session frame remeshed_graph;
    camera = Easy_camera.create ~target:Vec3.zero ~distance:5.2
        ~azimuth:0.55 ~elevation:0.32 ();
    frames_left = if Sketch.is_headless () then Some 2 else None;
  }

let update model frame =
  let frames_left = match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None in
  { model with camera = Easy_camera.update model.camera frame; frames_left }

let wire = Material.unlit (Color.hex_exn "#67e8f9")
let surface = Material.create ~diffuse:(Color.hex_exn "#f59e0b")
    ~ambient:(Color.hex_exn "#451a03") ~specular:Color.white ~shininess:42. ()

let lights = [
  Light.directional ~direction:(Vec3.create (-0.5) (-1.) (-0.65))
    ~diffuse:(Color.hex_exn "#fff7ed")
    ~ambient:(Color.hex_exn "#172554") ();
]

let view model _frame =
  let scene = Scene3.create ~lights ~samples:4 [
    Scene3.translate (Vec3.create (-1.45) 0. 0.) [
      Scene3.mesh ~mode:Scene3.Wireframe ~material:wire model.input;
    ];
    Scene3.translate (Vec3.create 1.45 0. 0.) [
      Scene3.mesh ~cull:Scene3.Cull_none ~material:surface model.remeshed;
      Scene3.mesh ~mode:Scene3.Wireframe ~material:wire model.remeshed;
    ];
  ] in
  Scene.[
    clear (Color.hex_exn "#020617");
    view3d ~camera:(Easy_camera.camera model.camera) scene;
    text ~at:(22, 18) "Input";
    text ~at:(470, 18) "Isotropic remesh";
    text ~at:(22, 552)
      "Drag to orbit · middle-drag to pan · scroll to zoom";
  ]

let on_stop model = Session.close model.session

let () =
  ignore (Sketch.run_state
    ~config:{ Sketch.default_config with width = 900; height = 600;
      title = "Prismel Remesh" }
    ~init ~update ~view ~on_stop ())
