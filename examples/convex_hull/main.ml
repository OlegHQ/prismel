open Prismel
open Procedural

type model = {
  session : Session.t;
  hull : Mesh.t;
  camera : Easy_camera.t;
  frames_left : int option;
}

let cloud () =
  Array.init 6_000 (fun point ->
    let u = float_of_int point /. 6_000.
    and v = float_of_int ((point * 4_053 + 791) mod 6_001) /. 6_001. in
    let y = 2. *. u -. 1.
    and angle = 2. *. Float.pi *. v in
    let radial = sqrt (max 0. (1. -. (y *. y)))
    and shell = 0.55 +. (0.45 *. abs_float (sin (17. *. u +. 11. *. v))) in
    1.35 *. shell *. radial *. cos angle,
    shell *. y,
    0.82 *. shell *. radial *. sin angle)

let graph () =
  Sop.points (cloud ())
  |> Sop.convex_hull ~source_point_attribute:"source_point" ~hull_group:"hull"
  |> Sop.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:0.7

let cook session frame node =
  let context = Context.of_frame ~seed:2026L frame |> Result.get_ok in
  match Bridge.cook_to_mesh session ~context node with
  | Ok (mesh, _warnings) -> mesh
  | Error error -> failwith (Diagnostic.error_to_string error)

let init frame =
  let session = Session.create ~max_entries:8
      ~max_payload_bytes:(64 * 1024 * 1024) |> Result.get_ok in
  {
    session;
    hull = cook session frame (graph ());
    camera = Easy_camera.create ~target:Vec3.zero ~distance:4.8
        ~azimuth:0.7 ~elevation:0.35 ();
    frames_left = None;
  }

let update model frame =
  let frames_left = match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None in
  { model with camera = Easy_camera.update model.camera frame; frames_left }

let surface = Material.create ~diffuse:(Color.hex_exn "#a5b4fc")
    ~ambient:(Color.hex_exn "#172554") ~specular:Color.white ~shininess:36. ()
let wire = Material.unlit (Color.hex_exn "#312e81")

let lights = [
  Light.directional ~direction:(Vec3.create (-1.) (-1.2) (-2.))
    ~diffuse:Color.white ~ambient:(Color.hex_exn "#172554") ();
]

let view model _frame =
  Scene.[
    clear (Color.hex_exn "#020617");
    view3d ~camera:(Easy_camera.camera model.camera)
      (Scene3.create ~samples:4 ~lights [
        Scene3.mesh ~cull:Scene3.Cull_none ~material:surface model.hull;
        Scene3.mesh ~mode:Scene3.Wireframe ~material:wire model.hull;
      ]);
    text ~at:(22, 18) "Exact-predicate convex hull of 6,000 points";
    text ~at:(22, 552)
      "Drag to orbit · middle-drag to pan · scroll to zoom";
  ]

let on_stop model = Session.close model.session

let () =
  ignore (Sketch.run_state
    ~config:{ Sketch.default_config with width = 900; height = 600;
      title = "Prismel Convex Hull" }
    ~init ~update ~view ~on_stop ())
