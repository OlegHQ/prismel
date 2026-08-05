open Prismel
open Procedural

type model = {
  session : Session.t;
  curves : Mesh.t;
  cuts : Mesh.t;
  camera : Easy_camera.t;
  frames_left : int option;
}

let source () =
  let curve_count = 11 and points_per_curve = 161 in
  let point_count = curve_count * points_per_curve in
  let positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:(Array.init point_count (fun point ->
        let local = point mod points_per_curve in
        -3. +. (6. *. Float.of_int local
          /. Float.of_int (points_per_curve - 1))))
      ~y:(Array.init point_count (fun point ->
        let curve = point / points_per_curve in
        -1.5 +. (3. *. Float.of_int curve /. Float.of_int (curve_count - 1))))
      ~z:(Array.init point_count (fun point ->
        let curve = point / points_per_curve
        and local = point mod points_per_curve in
        0.16 *. sin ((Float.of_int local *. 0.13)
          +. (Float.of_int curve *. 0.31)))) in
  let topology = Pdk.Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (curve_count + 1)
        (fun primitive -> primitive * points_per_curve))
      ~primitive_kinds:(Array.make curve_count Pdk.Topology.Open_polyline)
      |> Result.get_ok in
  let signal = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point
      ~name:"signal" (Pdk.Attribute.Float (Array.init point_count (fun point ->
        let curve = point / points_per_curve
        and local = point mod points_per_curve in
        sin ((Float.of_int local *. 0.21) +. (Float.of_int curve *. 0.37)))))
      |> Result.get_ok in
  let cut = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Primitive
      ~name:"cut" (Pdk.Attribute.Float (Array.init curve_count (fun curve ->
        -0.35 +. (0.7 *. Float.of_int curve
          /. Float.of_int (curve_count - 1))))) |> Result.get_ok in
  Pdk.Geometry.create ~positions ~topology ~attributes:[signal;cut] ()
  |> Result.get_ok

let curve_graph source = source
    |> Sop.polywire ~sides:6 ~radius:0.018 ~caps:true
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#334155")

let cut_graph source =
  let targets = source
      |> Sop.extract_point_from_curve
        ~cut:(Sop.Extract_point_primitive_attribute "cut")
        ~distance_attribute:"signal" ~curve_u_attribute:"curveu"
        ~number_cuts_attribute:"cuts" ~curve_number_attribute:"curve" in
  let marker = Sop.uv_sphere ~segments:12 ~rings:6 ~radius:0.065 ()
      |> Sop.normals ~owner:Pdk.Attribute.Vertex
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#22d3ee") in
  Sop.copy_to_points ~source:marker ~targets ()

let cook session frame node =
  let context = Context.of_frame ~seed:2026L frame |> Result.get_ok in
  match Bridge.cook_to_mesh session ~context node with
  | Ok (mesh, _) -> mesh
  | Error error -> failwith (Diagnostic.error_to_string error)

let init frame =
  let session = Session.create ~max_entries:12
      ~max_payload_bytes:(64 * 1024 * 1024) |> Result.get_ok in
  let source = Sop.snapshot (source ()) in
  { session;
    curves = cook session frame (curve_graph source);
    cuts = cook session frame (cut_graph source);
    camera = Easy_camera.create ~target:Vec3.zero ~distance:6.2
      ~azimuth:0.15 ~elevation:0.25 ();
    frames_left = if Sketch.is_headless () then Some 2 else None }

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
        ~material:(Material.unlit Color.white) model.curves;
      Scene3.mesh ~cull:Scene3.Cull_none
        ~material:(Material.unlit Color.white) model.cuts]);
    text ~at:(20,18) "Extract Point from Curve: varying scalar cuts";
    text ~at:(20,552) "Drag to orbit · middle-drag to pan · scroll to zoom"]

let on_stop model = Session.close model.session

let () =
  ignore (Sketch.run_state
    ~config:{ Sketch.default_config with width=900; height=600;
      title="Prismel Extract Point from Curve" }
    ~init ~update ~view ~on_stop ())
