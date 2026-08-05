open Prismel
open Procedural

type model = {
  session : Session.t;
  geometry : Pdk.Geometry.t;
  frames_left : int option;
}

let authored_geometry () =
  let random_count = 180 and point_count = 184 in
  let points = Array.init point_count (fun point ->
    if point < random_count then begin
      let random = Rand.seed ((point * 101) + 29) in
      let x,random = Rand.float random in
      let y,_ = Rand.float random in
      let x = (x *. 700.) +. 50. and y = (y *. 430.) +. 80. in
      x,y,(x *. 0.18) +. (y *. 0.31)
    end else match point - random_count with
      | 0 -> 70.,100.,43.6 | 1 -> 730.,100.,162.4
      | 2 -> 730.,500.,286.4 | _ -> 70.,500.,167.6) in
  let positions = Pdk.Geometry.positions (Pdk.Ops.points points) in
  let topology = Pdk.Topology.create_owned ~point_count
      ~vertex_points:[|180;181;182;183; 180;182; 181;183|]
      ~primitive_offsets:[|0;4;6;8|]
      ~primitive_kinds:[|Pdk.Topology.Polygon;
        Pdk.Topology.Open_polyline;Pdk.Topology.Open_polyline|]
      |> Result.get_ok in
  let geometry = Pdk.Geometry.create ~positions ~topology () |> Result.get_ok in
  let constraints = Pdk.Group.init ~owner:Pdk.Group.Primitive
      ~name:"crossing_constraints" 3 (fun _ -> true) in
  Pdk.Geometry.with_group constraints geometry |> Result.get_ok

let init frame =
  let session = Session.create ~max_entries:4 ~max_payload_bytes:12_000_000
      |> Result.get_ok in
  let node = authored_geometry () |> Sop.snapshot
      |> Sop.triangulate_2d ~projection:Pdk.Ops.Triangulate_2d_best_fit
          ~seed:2026L ~constraint_primitive_group:"crossing_constraints"
          ~split_crossing_constraints:true ~flood_from_hull_boundary:true
          ~remove_outside_constraint_polygons:true
          ~silhouette_constraints:true ~remove_outside_silhouette:true
          ~refine:true ~minimum_angle:(Float.pi /. 12.)
          ~maximum_area:4_000. ~minimum_edge_length:4.
          ~maximum_new_points:256 ~regularization_steps:2
          ~refinement_point_group:"refined"
          ~split_point_group:"crossings"
          ~constraint_group:"constraints" ~triangle_group:"delaunay" in
  let context = Context.of_frame ~seed:2026L frame |> Result.get_ok in
  let geometry = match Session.cook session ~context node with
    | Ok output -> output.geometry
    | Error error -> failwith (Diagnostic.error_to_string error) in
  {session;geometry;
   frames_left=if Sketch.is_headless () then Some 2 else None}

let update model _ =
  let frames_left = match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None in
  {model with frames_left}

let palette = [|
  Color.hex_exn "#164e63"; Color.hex_exn "#831843";
  Color.hex_exn "#713f12"; Color.hex_exn "#4c1d95" |]

let view model _ =
  let positions = Pdk.Packed.Float3.Private.view
      (Pdk.Geometry.positions model.geometry)
  and topology = Pdk.Topology.Private.view
      (Pdk.Geometry.topology model.geometry) in
  let triangles = List.init (Pdk.Geometry.primitive_count model.geometry)
      (fun primitive ->
        let vertex = topology.primitive_offsets.(primitive) in
        let point local =
          let point = topology.vertex_points.(vertex + local) in
          int_of_float positions.x.(point),int_of_float positions.y.(point) in
        Scene.triangle (point 0) (point 1) (point 2)
          ~fill:palette.(primitive mod Array.length palette)
          ~stroke:(Color.hex_exn "#67e8f9") ()) in
  let constraints = match Pdk.Geometry.find_edge_group "constraints" model.geometry with
    | None -> []
    | Some group ->
        let index = Pdk.Topology_index.create (Pdk.Geometry.topology model.geometry) in
        let view = Pdk.Topology_index.Private.view index in
        let lines = ref [] in
        Pdk.Edge_group.iter (fun edge ->
          let point index =
            int_of_float positions.x.(index),int_of_float positions.y.(index) in
          lines := Scene.line ~from_:(point view.edge_a.(edge))
              ~to_:(point view.edge_b.(edge)) ~width:4
              ~color:(Color.hex_exn "#fbbf24") () :: !lines) group;
        List.rev !lines in
  let crossings = match Pdk.Geometry.find_group ~owner:Pdk.Group.Point
      "crossings" model.geometry with
    | None -> []
    | Some group ->
        let points = ref [] in
        Pdk.Group.iter (fun point ->
          points := Scene.circle
              ~at:(int_of_float positions.x.(point),int_of_float positions.y.(point))
              ~radius:7 ~fill:(Color.hex_exn "#fb7185") () :: !points) group;
        List.rev !points in
  [Scene.clear (Color.hex_exn "#020617");
   Scene.text ~at:(30,24) ~size:22
     "Triangulate 2D: exact constrained Delaunay refinement";
   Scene.text ~at:(30,52)
     "Gold boundary flood-clips the mesh; red marks the exact diagonal split"]
  @ triangles @ constraints @ crossings

let on_stop model = Session.close model.session

let () =
  ignore (Sketch.run_state
    ~config:{Sketch.default_config with width=800;height=560;
      title="Prismel Triangulate 2D"}
    ~init ~update ~view ~on_stop ())
