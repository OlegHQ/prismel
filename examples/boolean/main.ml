open Prismel
open Procedural

type model = {
  session : Session.t;
  mesh : Mesh.t;
  camera : Easy_camera.t;
  frames_left : int option;
}

let graph () =
  let left = Sop.box ~size:(Vec3.create 2.8 2.2 2.2)
      ~connectivity:Pdk.Ops.Box_quads ~consolidate_points:true
      ~normals:Pdk.Ops.Box_no_normals ()
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#38bdf8")
  and right = Sop.box ~size:(Vec3.create 2.2 1.15 1.15)
      ~center:(Vec3.create 0.85 0. 0.)
      ~rotation:(Vec3.create 0.35 0.42 0.12)
      ~connectivity:Pdk.Ops.Box_quads ~consolidate_points:true
      ~normals:Pdk.Ops.Box_no_normals () in
  Sop.boolean ~operation:Pdk.Boolean.Difference
    ~detriangulation:Pdk.Boolean.All_polygons ~right left
  |> Sop.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:1.0

let cook session frame =
  let context = Context.of_frame ~seed:2026L frame |> Result.get_ok in
  match Bridge.cook_to_mesh session ~context (graph ()) with
  | Ok (mesh, _warnings) -> mesh
  | Error error -> failwith (Diagnostic.error_to_string error)

let init frame =
  let session = Session.create ~max_entries:8
      ~max_payload_bytes:(64 * 1024 * 1024) |> Result.get_ok in
  {
    session;
    mesh = cook session frame;
    camera = Easy_camera.create ~target:Vec3.zero ~distance:5.5
        ~azimuth:0.65 ~elevation:0.38 ();
    frames_left = None;
  }

let update model frame =
  let frames_left = match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None in
  { model with camera = Easy_camera.update model.camera frame; frames_left }

let material = Material.create ~diffuse:Color.white
    ~ambient:(Color.hex_exn "#0c4a6e") ~specular:Color.white ~shininess:36. ()

let lights = [
  Light.directional ~direction:(Vec3.create (-0.7) (-1.2) (-1.5))
    ~diffuse:Color.white ~ambient:(Color.hex_exn "#172554") ();
]

let view model _frame = Scene.[
  clear (Color.hex_exn "#020617");
  view3d ~camera:(Easy_camera.camera model.camera)
    (Scene3.create ~samples:4 ~lights [
      Scene3.mesh ~cull:Scene3.Cull_none ~material model.mesh]);
  text ~at:(22, 18) "Exact Boolean difference";
  text ~at:(22, 44) "A rotated box is subtracted from the blue solid";
  text ~at:(22, 552) "Drag to orbit · middle-drag to pan · scroll to zoom";
]

let on_stop model = Session.close model.session

let () =
  ignore (Sketch.run_state
    ~config:{ Sketch.default_config with width = 900; height = 600;
      title = "Prismel Exact Boolean" }
    ~init ~update ~view ~on_stop ())
