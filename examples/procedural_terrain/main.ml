open Prismel
open Procedural

(* grid -> deterministic noise displacement -> height color *)

type model = {
  session : Session.t;
  graph : Node.t;
  mesh : Mesh.t;
  camera : Easy_camera.t;
  frames_left : int option;
}

let fail error = failwith (Diagnostic.error_to_string error)

let cook session graph frame =
  let context = Context.of_frame ~seed:42L frame |> Result.get_ok in
  match Bridge.cook_to_mesh session ~context graph with
  | Ok (mesh, _warnings) -> mesh
  | Error error -> fail error

let init frame =
  let graph =
    Sop.grid ~label:"terrain grid" ~columns:180 ~rows:180 ~size:12. ()
    |> Sop.noise_displace ~label:"mountains" ~seed:42
         ~amplitude:1.25 ~frequency:0.22
    |> Sop.color_by_height ~label:"height palette"
         ~low:(Color.hex_exn "#172554") ~high:(Color.hex_exn "#fbbf24")
  in
  let session = Session.create ~max_entries:64
      ~max_payload_bytes:(128 * 1024 * 1024) |> Result.get_ok in
  {
    session;
    graph;
    mesh = cook session graph frame;
    camera = Easy_camera.create ~target:(Vec3.create 0. 0. 0.)
        ~distance:11. ~azimuth:0.65 ~elevation:0.52 ();
    frames_left = if Sketch.is_headless () then Some 2 else None;
  }

let update model frame =
  let frames_left = match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None in
  {
    model with
    mesh = cook model.session model.graph frame;
    camera = Easy_camera.update model.camera frame;
    frames_left;
  }

let lights = [
  Light.directional ~direction:(Vec3.create (-0.4) (-1.) (-0.5))
    ~diffuse:(Color.hex_exn "#fff7ed")
    ~ambient:(Color.hex_exn "#1e293b") ();
]

let view model _frame =
  let scene = Scene3.create ~lights ~samples:4 [
    Scene3.mesh ~cull:Scene3.Cull_none
      ~material:(Material.create ~diffuse:Color.white ()) model.mesh;
  ] in
  Scene.[
    clear (Color.hex_exn "#020617");
    view3d ~camera:(Easy_camera.camera model.camera) scene;
    text ~at:(16, 16)
      "Procedural terrain — drag to orbit, middle-drag to pan, scroll to zoom";
  ]

let on_stop model = Session.close model.session

let () =
  ignore (Sketch.run_state
    ~config:{ Sketch.default_config with
      width = 900; height = 600; title = "Prismel Procedural Terrain" }
    ~init ~update ~view ~on_stop ())
