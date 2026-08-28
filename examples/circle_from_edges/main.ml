open Prismel
open Procedural

type model = {
  session : Session.t;
  source : Mesh.t;
  fitted : Mesh.t;
  camera : Easy_camera.t;
  frames_left : int option;
}

let source_geometry () =
  let loops = 5 and points_per_loop = 96 in
  let point_count = loops * points_per_loop in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. in
  for loop = 0 to loops - 1 do
    let center_x = -3. +. (1.5 *. float_of_int loop) in
    for local = 0 to points_per_loop - 1 do
      let point = (loop * points_per_loop) + local
      and angle = 2. *. Float.pi *. float_of_int local
          /. float_of_int points_per_loop in
      let radius = 0.72 +. (0.12 *. sin ((3. +. float_of_int loop) *. angle)) in
      let px = radius *. cos angle and py = radius *. sin angle in
      x.(point) <- center_x +. px;
      y.(point) <- py *. cos (0.11 *. float_of_int loop);
      z.(point) <- (py *. sin (0.11 *. float_of_int loop))
          +. (0.08 *. cos (2. *. angle))
    done
  done;
  let topology = Pdk.Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (loops + 1)
        (fun primitive -> primitive * points_per_loop))
      ~primitive_kinds:(Array.make loops Pdk.Topology.Closed_polyline)
      |> Result.get_ok in
  Pdk.Geometry.create
    ~positions:(Pdk.Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> Result.get_ok

let wire ~radius ~color node =
  node |> Sop.polywire ~sides:6 ~radius ~caps:false
  |> Sop.normals ~owner:Pdk.Attribute.Vertex
  |> Sop.set_color ~owner:Pdk.Attribute.Point color

let cook session frame node =
  let context = Context.of_frame ~seed:2026L frame |> Result.get_ok in
  match Bridge.cook_to_mesh session ~context node with
  | Ok (mesh, _) -> mesh
  | Error error -> failwith (Diagnostic.error_to_string error)

let init frame =
  let session = Session.create ~max_entries:12
      ~max_payload_bytes:(64 * 1024 * 1024) |> Result.get_ok in
  let source = Sop.snapshot (source_geometry ()) in
  let original = wire ~radius:0.018 ~color:(Color.hex_exn "#475569") source in
  let circles = source |> Sop.circle_from_edges
      ~scale:(Vec3.create 1. 0.72 1.) ~output_group:"fitted_edges"
      |> wire ~radius:0.032 ~color:(Color.hex_exn "#22d3ee") in
  { session; source = cook session frame original;
    fitted = cook session frame circles;
    camera = Easy_camera.create ~target:Vec3.zero ~distance:8.
      ~azimuth:0.1 ~elevation:0.35 ();
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
        ~material:(Material.unlit Color.white) model.source;
      Scene3.mesh ~cull:Scene3.Cull_none
        ~material:(Material.unlit Color.white) model.fitted]);
    text ~at:(20,18) "Circle from Edges: distorted loops → best-fit circles";
    text ~at:(20,552) "Drag to orbit · middle-drag to pan · scroll to zoom"]

let on_stop model = Session.close model.session

let () =
  ignore (Sketch.run_state
    ~config:{ Sketch.default_config with width=900; height=600;
      title="Prismel Circle from Edges" }
    ~init ~update ~view ~on_stop ())
