open Prismel
open Procedural

type model = {
  session : Session.t;
  box : Mesh.t;
  centers : Mesh.t;
  camera : Easy_camera.t;
  frames_left : int option;
}

let box_graph () =
  Sop.box ~size:(Vec3.create 2.4 1.8 2.) ~connectivity:Pdk.Ops.Box_quads
    ~consolidate_points:true ()
  |> Sop.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:0.1

let centers_graph () =
  let targets = box_graph ()
      |> Sop.extract_centroid ~run_over:Pdk.Ops.Centroid_primitives
        ~method_:Pdk.Ops.Centroid_bounding_box
        ~source_primitive_attribute:"sourceprim" in
  let marker = Sop.uv_sphere ~segments:16 ~rings:8 ~radius:0.12 ()
      |> Sop.normals ~owner:Pdk.Attribute.Vertex in
  Sop.copy_to_points ~source:marker ~targets ()

let cook session frame node =
  let context = Context.of_frame ~seed:2026L frame |> Result.get_ok in
  match Bridge.cook_to_mesh session ~context node with
  | Ok (mesh, _) -> mesh
  | Error error -> failwith (Diagnostic.error_to_string error)

let init frame =
  let session = Session.create ~max_entries:12
      ~max_payload_bytes:(32 * 1024 * 1024) |> Result.get_ok in
  { session; box = cook session frame (box_graph ());
    centers = cook session frame (centers_graph ());
    camera = Easy_camera.create ~target:Vec3.zero ~distance:5.
      ~azimuth:0.75 ~elevation:0.4 ();
    frames_left = None }

let update model frame =
  let frames_left = match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None in
  { model with camera = Easy_camera.update model.camera frame; frames_left }

let view model _ =
  let camera = Easy_camera.camera model.camera in
  Scene.[clear (Color.hex_exn "#020617");
    view3d ~camera (Scene3.create ~samples:4 [
      Scene3.mesh ~cull:Scene3.Cull_none
        ~material:(Material.unlit (Color.hex_exn "#334155")) model.box;
      Scene3.mesh ~mode:Scene3.Wireframe
        ~material:(Material.unlit (Color.hex_exn "#94a3b8")) model.box;
      Scene3.mesh ~cull:Scene3.Cull_none
        ~material:(Material.unlit (Color.hex_exn "#f59e0b")) model.centers]);
    text ~at:(20,18) "Extract Centroid: one marker per polygon face";
    text ~at:(20,552) "Drag to orbit · middle-drag to pan · scroll to zoom"]

let on_stop model = Session.close model.session

let () =
  ignore (Sketch.run_state
    ~config:{ Sketch.default_config with width=900; height=600;
      title="Prismel Extract Centroid" }
    ~init ~update ~view ~on_stop ())
