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
  let detected = source
      |> Sop.boolean_detect ~collision ~include_coplanar:false
           ~intersecting_group:(Some "crossing_faces")
           ~intersections_attribute:"collision_primitives"
           ~count_attribute:"intersection_count" in
  let surface = detected
      |> Sop.blast ~owner:Pdk.Group.Primitive ~group:"crossing_faces"
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#2563eb")
  and crossings = detected
      |> Sop.blast ~selected:false ~owner:Pdk.Group.Primitive
           ~group:"crossing_faces"
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fb923c")
  and collision = collision
      |> Sop.group ~name:"crossing_faces" Select.all_primitives
      |> Sop.set_int ~owner:Pdk.Attribute.Primitive
           ~name:"intersection_count" 0
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#14b8a6") in
  (* Delete the ragged output before merging because the collision display has
     no meaningful source-to-collision rows of its own. *)
  let surface = Sop.delete_attribute ~owner:Pdk.Attribute.Primitive
      ~name:"collision_primitives" surface
  and crossings = Sop.delete_attribute ~owner:Pdk.Attribute.Primitive
      ~name:"collision_primitives" crossings in
  Sop.merge [surface; crossings; collision]

let init frame =
  let session = Session.create ~max_entries:12
      ~max_payload_bytes:(96 * 1024 * 1024) |> Result.get_ok in
  {
    session;
    mesh = cook session frame (graph ());
    camera = Easy_camera.create ~target:Vec3.zero ~distance:5.8
        ~azimuth:0.7 ~elevation:0.38 ();
    frames_left = None;
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
    text ~at:(22, 18) "Boolean Detect";
    text ~at:(22, 44)
      "Orange source faces intersect the teal collision surface";
    text ~at:(22, 552)
      "Drag to orbit · middle-drag to pan · scroll to zoom";
  ]

let on_stop model = Session.close model.session

let () =
  ignore (Sketch.run_state
    ~config:{ Sketch.default_config with width = 900; height = 600;
      title = "Prismel Boolean Detect" }
    ~init ~update ~view ~on_stop ())
