open Prismel
open Procedural

type model = {
  session : Session.t;
  mesh : Mesh.t;
  camera : Easy_camera.t;
  frames_left : int option;
}

let cook session frame graph =
  let context = Context.of_frame ~seed:2026L frame |> Result.get_ok in
  match Bridge.cook_to_mesh session ~context graph with
  | Ok (mesh, _warnings) -> mesh
  | Error error -> failwith (Diagnostic.error_to_string error)

let graph () =
  let source = Sop.grid ~counts:Pdk.Ops.Grid_point_counts
      ~connectivity:Pdk.Ops.Grid_alternating_triangles
      ~columns:72 ~rows:54 ~size:3.8 () in
  let collision = source
      |> Sop.transform (Mat4.mul (Mat4.rotation_z 0.18)
          (Mat4.rotation_x 1.08)) in
  let curve_a = Sop.polyline [|-1.4,1.35,-0.55; 1.4,1.35,0.55|]
  and curve_b = Sop.polyline [|-1.4,1.35,0.55; 1.4,1.35,-0.55|] in
  let intersections = Sop.merge [
      Sop.intersection_analysis ~collision ~include_coplanar:false source;
      Sop.intersection_analysis ~collision:curve_b curve_a] in
  let marker = Sop.uv_sphere ~connectivity:Pdk.Ops.Sphere_triangles
      ~segments:9 ~rings:6 ~radius:0.045 ()
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fb923c") in
  let markers = Sop.copy_to_points ~source:marker ~targets:intersections () in
  let source = source |> Sop.set_color ~owner:Pdk.Attribute.Point
      (Color.hex_exn "#2563eb")
  and collision = collision |> Sop.set_color ~owner:Pdk.Attribute.Point
      (Color.hex_exn "#14b8a6")
  and curve_a = curve_a |> Sop.polywire ~sides:6 ~generate_uv:false
      ~caps:false ~radius:0.018
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f8fafc")
  and curve_b = curve_b |> Sop.polywire ~sides:6 ~generate_uv:false
      ~caps:false ~radius:0.018
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f8fafc") in
  Sop.merge [source; collision; curve_a; curve_b; markers]

let init frame =
  let session = Session.create ~max_entries:12
      ~max_payload_bytes:(96 * 1024 * 1024) |> Result.get_ok in
  {
    session;
    mesh = cook session frame (graph ());
    camera = Easy_camera.create ~target:Vec3.zero ~distance:5.8
        ~azimuth:0.7 ~elevation:0.38 ();
    frames_left = if Sketch.is_headless () then Some 2 else None;
  }

let update model frame =
  let frames_left = match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None in
  { model with camera = Easy_camera.update model.camera frame; frames_left }

let material = Material.create ~diffuse:Color.white
    ~ambient:(Color.hex_exn "#172554") ~specular:Color.white ~shininess:30. ()

let lights = [
  Light.directional ~direction:(Vec3.create (-1.) (-1.4) (-2.))
    ~diffuse:Color.white ~ambient:(Color.hex_exn "#172554") ();
]

let view model _frame =
  Scene.[
    clear (Color.hex_exn "#020617");
    view3d ~camera:(Easy_camera.camera model.camera)
      (Scene3.create ~samples:4 ~lights [
        Scene3.mesh ~cull:Scene3.Cull_none ~material model.mesh]);
    text ~at:(22, 18) "Intersection Analysis";
    text ~at:(22, 44)
      "Orange points are welded surface/curve intersections with primitive/UVW provenance";
    text ~at:(22, 552)
      "Drag to orbit · middle-drag to pan · scroll to zoom";
  ]

let on_stop model = Session.close model.session

let () =
  ignore (Sketch.run_state
    ~config:{ Sketch.default_config with width = 900; height = 600;
      title = "Prismel Intersection Analysis" }
    ~init ~update ~view ~on_stop ())
