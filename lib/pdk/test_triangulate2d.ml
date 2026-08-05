open Prismel
open Pdk

let fail message = prerr_endline ("test_triangulate2d: " ^ message); exit 1
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error error -> fail (Error.to_string error)

let topology_signature geometry =
  let topology = Topology.Private.view (Geometry.topology geometry) in
  Array.copy topology.vertex_points,Array.copy topology.primitive_offsets

let test_xy_payload_and_group () =
  let input = Ops.points [|0.,0.,3.; 1.,0.,4.; 1.,1.,5.; 0.,1.,6.|]
      in
  let id = Attribute.create_owned ~name:"id" ~owner:Attribute.Point
      (Attribute.Int [|10;11;12;13|]) |> Result.get_ok in
  let selected = Group.init ~owner:Group.Point ~name:"selected" 4 (fun _ -> true) in
  let input = Geometry.with_attribute id input |> Result.get_ok
      |> Geometry.with_group selected |> Result.get_ok in
  let output = Ops.triangulate_2d ~projection:Ops.Triangulate_2d_xy
      ~triangle_group:"triangles" input |> get in
  check (Geometry.point_count output = 4 && Geometry.primitive_count output = 2
      && Geometry.vertex_count output = 6) "XY cardinality";
  check (Geometry.positions output == Geometry.positions input)
    "positions were not structurally shared";
  check (Option.is_some (Geometry.find_attribute ~owner:Attribute.Point "id" output))
    "point payload was dropped";
  check (Option.is_some (Geometry.find_group ~owner:Group.Point "selected" output))
    "point group was dropped";
  match Geometry.find_group ~owner:Group.Primitive "triangles" output with
  | Some group -> check (Group.cardinality group = 2) "triangle group cardinality"
  | None -> fail "triangle group is missing"

let test_best_fit_and_explicit_plane () =
  let input = Ops.points [|0.,0.,0.; 1.,0.,1.; 1.,1.,3.; 0.,1.,2.; 0.5,0.5,1.5|]
      in
  let best = Ops.triangulate_2d input |> get in
  check (Geometry.primitive_count best = 4) "best-fit tilted plane cardinality";
  let explicit = Ops.triangulate_2d
      ~projection:(Ops.Triangulate_2d_plane {
        origin = Vec3.zero; normal = Vec3.create (-1.) (-2.) 1. }) input |> get in
  check (Geometry.primitive_count explicit = 4)
    "explicit tilted plane cardinality"

let test_attribute_and_selection () =
  let input = Ops.points [|0.,0.,0.; 1.,0.,0.; 2.,0.,0.; 3.,0.,0.; 4.,0.,0.|]
      in
  let uv = Packed.Float2.of_owned ~x:[|0.;1.;1.;0.;5.|]
      ~y:[|0.;0.;1.;1.;5.|] |> Result.get_ok in
  let uv = Attribute.create_owned ~name:"planar" ~owner:Attribute.Point
      (Attribute.Float2 uv) |> Result.get_ok in
  let input = Geometry.with_attribute uv input |> Result.get_ok in
  let group = Group.ordered ~owner:Group.Point ~name:"four" ~length:5
      [|0;1;2;3|] |> Result.get_ok in
  let output = Ops.triangulate_2d
      ~selection:(Ops.Selected_points group)
      ~projection:(Ops.Triangulate_2d_point_attribute "planar") input |> get in
  check (Geometry.primitive_count output = 2) "attribute/selection cardinality";
  let topology = Topology.Private.view (Geometry.topology output) in
  check (Array.for_all (fun point -> point < 4) topology.vertex_points)
    "unselected point entered triangulation"

let constrained_square () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;1.;0.|] ~y:[|0.;0.;1.;1.|] ~z:[|0.;0.;0.;0.|] in
  let topology = Topology.create_owned ~point_count:4
      ~vertex_points:[|1;3|] ~primitive_offsets:[|0;2|]
      ~primitive_kinds:[|Topology.Open_polyline|] |> Result.get_ok in
  let geometry = Geometry.create ~positions ~topology () |> Result.get_ok in
  let primitives = Group.init ~owner:Group.Primitive ~name:"constraint" 1
      (fun _ -> true) in
  geometry,primitives

let check_constraint_edge geometry =
  match Geometry.find_edge_group "constraints" geometry with
  | None -> fail "constraint output group is missing"
  | Some group ->
      check (Edge_group.cardinality group = 1) "constraint group cardinality";
      let index = Topology_index.create (Geometry.topology geometry) in
      let edge = Topology_index.find_edge_index index ~a:1 ~b:3 in
      check (edge >= 0 && Edge_group.mem edge group) "forced constraint edge is missing"

let test_constraints () =
  let input,primitives = constrained_square () in
  let output = Ops.triangulate_2d ~projection:Ops.Triangulate_2d_xy
      ~constraint_primitives:primitives ~constraint_group:"constraints" input
      |> get in
  check_constraint_edge output;
  let source_index = Topology_index.create (Geometry.topology input) in
  let edge = Topology_index.find_edge_index source_index ~a:1 ~b:3 in
  let edges = Edge_group.init ~topology:(Geometry.topology input)
      ~index:source_index ~name:"edge_constraint" (fun candidate -> candidate = edge) in
  let output = Ops.triangulate_2d ~projection:Ops.Triangulate_2d_xy
      ~constraint_edges:edges ~constraint_group:"constraints" input |> get in
  check_constraint_edge output;
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;2.;0.;2.;1.|] ~y:[|0.;0.;0.;2.;2.;1.|]
      ~z:[|0.;0.;0.;0.;0.;0.|] in
  let topology = Topology.create_owned ~point_count:6
      ~vertex_points:[|0;2|] ~primitive_offsets:[|0;2|]
      ~primitive_kinds:[|Topology.Open_polyline|] |> Result.get_ok in
  let geometry = Geometry.create ~positions ~topology () |> Result.get_ok in
  let primitives = Group.init ~owner:Group.Primitive ~name:"embedded" 1
      (fun _ -> true) in
  let run domains = Parallel.run ~domains (fun () ->
      Ops.triangulate_2d ~grain:1 ~projection:Ops.Triangulate_2d_xy
        ~constraint_primitives:primitives ~constraint_group:"constraints"
        geometry |> get) in
  let embedded = run 1 and parallel = run 4 in
  check (Geometry.point_count embedded = 6)
    "authored constraint point was materialized as a new point";
  check (topology_signature embedded = topology_signature parallel)
    "embedded constraint point differs across domains";
  (match Geometry.find_edge_group "constraints" embedded with
   | Some group -> check (Edge_group.cardinality group = 2)
       "embedded point did not split the output constraint"
   | None -> fail "embedded constraint output group is missing")

let crossing_constraints () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;2.;2.;0.|] ~y:[|0.;0.;2.;2.|] ~z:[|0.;100.;10.;200.|] in
  let topology = Topology.create_owned ~point_count:4
      ~vertex_points:[|0;2; 1;3|] ~primitive_offsets:[|0;2;4|]
      ~primitive_kinds:[|Topology.Open_polyline;Topology.Open_polyline|]
      |> Result.get_ok in
  let weight = Attribute.create_owned ~name:"weight" ~owner:Attribute.Point
      (Attribute.Float [|0.;100.;10.;200.|]) |> Result.get_ok
  and id = Attribute.create_owned ~name:"id" ~owner:Attribute.Point
      (Attribute.Int [|10;11;12;13|]) |> Result.get_ok
  and label = Attribute.create_owned ~name:"label" ~owner:Attribute.Point
      (Attribute.Text [|"a";"b";"c";"d"|]) |> Result.get_ok in
  let selected = Group.init ~owner:Group.Point ~name:"selected" 4
      (fun point -> point = 2) in
  let constraints = Group.init ~owner:Group.Primitive ~name:"constraints" 2
      (fun _ -> true) in
  Geometry.create ~positions ~topology ~attributes:[weight;id;label]
    ~groups:[selected;constraints] () |> Result.get_ok,constraints

let test_crossing_constraints_and_payload () =
  let input,constraints = crossing_constraints () in
  (match Ops.triangulate_2d ~projection:Ops.Triangulate_2d_xy
      ~constraint_primitives:constraints input with
   | Error _ -> ()
   | Ok _ -> fail "crossing constraints succeeded without opt-in splitting");
  (match Ops.triangulate_2d ~projection:Ops.Triangulate_2d_xy
      ~constraint_primitives:constraints ~split_crossing_constraints:true
      ~refine:true ~maximum_new_points:0 input with
   | Error _ -> ()
   | Ok _ -> fail "required arrangement split escaped the refinement budget");
  let run domains = Parallel.run ~domains (fun () ->
      Ops.triangulate_2d ~grain:1 ~projection:Ops.Triangulate_2d_xy
        ~constraint_primitives:constraints ~split_crossing_constraints:true
        ~split_point_group:"crossings" ~constraint_group:"constraints" input
      |> get) in
  let output = run 1 and parallel = run 4 in
  check (Geometry.point_count output = 5
      && Geometry.primitive_count output = 4
      && Geometry.vertex_count output = 12) "crossing output cardinality";
  check (topology_signature output = topology_signature parallel)
    "crossing one/four-domain topology differs";
  let positions = Packed.Float3.Private.view (Geometry.positions output) in
  check (positions.x.(4) = 1. && positions.y.(4) = 1. && positions.z.(4) = 5.)
    "crossing 3D interpolation";
  let float_attribute name geometry =
    match Geometry.find_attribute ~owner:Attribute.Point name geometry with
    | Some attribute -> (match Attribute.Private.storage attribute with
        | Attribute.Float values -> values | _ -> fail "float storage changed")
    | None -> fail ("missing point attribute " ^ name) in
  let int_attribute name geometry =
    match Geometry.find_attribute ~owner:Attribute.Point name geometry with
    | Some attribute -> (match Attribute.Private.storage attribute with
        | Attribute.Int values -> values | _ -> fail "integer storage changed")
    | None -> fail ("missing point attribute " ^ name) in
  let text_attribute name geometry =
    match Geometry.find_attribute ~owner:Attribute.Point name geometry with
    | Some attribute -> (match Attribute.Private.storage attribute with
        | Attribute.Text values -> values | _ -> fail "text storage changed")
    | None -> fail ("missing point attribute " ^ name) in
  let weights = float_attribute "weight" output
  and parallel_weights = float_attribute "weight" parallel in
  check (weights = parallel_weights && weights.(4) = 5.)
    "crossing float payload interpolation";
  check ((int_attribute "id" output).(4) = 12
      && (text_attribute "label" output).(4) = "c")
    "crossing discrete payload policy";
  (match Geometry.find_group ~owner:Group.Point "selected" output with
   | Some group -> check (Group.mem 4 group) "split point group ancestry"
   | None -> fail "source point group was dropped");
  (match Geometry.find_group ~owner:Group.Point "crossings" output with
   | Some group -> check (Group.cardinality group = 1 && Group.mem 4 group)
       "split output group"
   | None -> fail "split output group is missing");
  (match Geometry.find_edge_group "constraints" output with
   | Some group -> check (Edge_group.cardinality group = 4)
       "split constraint edge cardinality"
   | None -> fail "split constraint output group is missing");
  let authored_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;2.;2.;0.;1.|] ~y:[|0.;0.;2.;2.;1.|]
      ~z:[|0.;0.;0.;0.;7.|] in
  let authored_topology = Topology.create_owned ~point_count:5
      ~vertex_points:[|0;2;1;3|] ~primitive_offsets:[|0;2;4|]
      ~primitive_kinds:[|Topology.Open_polyline;Topology.Open_polyline|]
      |> Result.get_ok in
  let authored = Geometry.create ~positions:authored_positions
      ~topology:authored_topology () |> Result.get_ok in
  let authored_constraints = Group.init ~owner:Group.Primitive
      ~name:"authored_crossing" 2 (fun _ -> true) in
  let authored = Ops.triangulate_2d ~grain:1
      ~projection:Ops.Triangulate_2d_xy
      ~constraint_primitives:authored_constraints
      ~split_crossing_constraints:true ~split_point_group:"generated"
      ~constraint_group:"constraints" authored |> get in
  check (Geometry.point_count authored = 5
      && Geometry.primitive_count authored = 4)
    "authored crossing point was duplicated by exact construction";
  (match Geometry.find_group ~owner:Group.Point "generated" authored with
   | Some group -> check (Group.cardinality group = 0)
       "authored crossing point was marked as generated"
   | None -> fail "authored crossing generated-point group is missing");
  (match Geometry.find_edge_group "constraints" authored with
   | Some group -> check (Edge_group.cardinality group = 4)
       "authored crossing constraint cardinality"
   | None -> fail "authored crossing constraint group is missing")

let test_hull_boundary_flood () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|-2.;2.;2.;-2.; -1.;1.;1.;-1.; 0.|]
      ~y:[|-2.;-2.;2.;2.; -1.;-1.;1.;1.; 0.|]
      ~z:[|0.;0.;0.;0.;0.;0.;0.;0.;0.|] in
  let topology = Topology.create_owned ~point_count:9
      ~vertex_points:[|4;5;6;7|] ~primitive_offsets:[|0;4|]
      ~primitive_kinds:[|Topology.Closed_polyline|] |> Result.get_ok in
  let constraint_group = Group.init ~owner:Group.Primitive ~name:"boundary" 1
      (fun _ -> true) in
  let input = Geometry.create ~positions ~topology ~groups:[constraint_group] ()
      |> Result.get_ok in
  let run domains = Parallel.run ~domains (fun () ->
      Ops.triangulate_2d ~grain:1 ~projection:Ops.Triangulate_2d_xy
        ~constraint_primitives:constraint_group ~flood_from_hull_boundary:true
        ~constraint_group:"boundary" input |> get) in
  let output = run 1 and parallel = run 4 in
  check (topology_signature output = topology_signature parallel)
    "hull flood one/four-domain topology differs";
  check (Geometry.primitive_count output = 4)
    "hull flood retained the wrong triangle count";
  let view = Topology.Private.view (Geometry.topology output) in
  check (Array.for_all (fun point -> point >= 4) view.vertex_points)
    "hull flood retained exterior geometry";
  (match Geometry.find_edge_group "boundary" output with
   | Some group -> check (Edge_group.cardinality group = 4)
       "hull flood constrained-edge cardinality"
   | None -> fail "hull flood constraint group is missing");
  let polygon = Ops.triangulate_2d ~grain:1
      ~projection:Ops.Triangulate_2d_xy
      ~constraint_primitives:constraint_group
      ~remove_outside_constraint_polygons:true
      ~constraint_group:"boundary" input |> get in
  check (topology_signature polygon = topology_signature output)
    "constraint-polygon winding differs from simple hull-flood interior";
  let empty = Ops.triangulate_2d ~projection:Ops.Triangulate_2d_xy
      ~flood_from_hull_boundary:true (Ops.points [|0.,0.,0.;1.,0.,0.;0.,1.,0.|])
      |> get in
  check (Geometry.primitive_count empty = 0)
    "unblocked adapter hull flood did not remove all triangles";
  let edge_only = Ops.triangulate_2d ~projection:Ops.Triangulate_2d_xy
      ~constraint_edges:(let index = Topology_index.create topology in
        Edge_group.init ~topology ~index ~name:"edge_only" (fun _ -> true))
      ~remove_outside_constraint_polygons:true input |> get in
  check (Geometry.primitive_count edge_only = 0)
    "edge-only constraints incorrectly contributed polygon winding"

let test_ignore_non_constraint_points () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;2.;2.;0.;1.|] ~y:[|0.;0.;2.;2.;1.|]
      ~z:[|0.;0.;0.;0.;9.|] in
  let topology = Topology.polygons_owned ~point_count:5
      ~vertex_points:[|0;1;2;3|] ~primitive_offsets:[|0;4|]
      |> Result.get_ok in
  let authored_normal = Attribute.create_owned ~name:"N" ~owner:Attribute.Point
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:(Array.make 5 1.) ~y:(Array.make 5 0.) ~z:(Array.make 5 0.)))
      |> Result.get_ok in
  let input = Geometry.create ~positions ~topology ~attributes:[authored_normal] ()
      |> Result.get_ok in
  let boundary = Group.init ~owner:Group.Primitive ~name:"boundary" 1
      (fun _ -> true) in
  let ordinary = Ops.triangulate_2d ~projection:Ops.Triangulate_2d_xy
      ~constraint_primitives:boundary input |> get in
  check (Geometry.primitive_count ordinary = 4)
    "ordinary triangulation did not include the interior point";
  let run domains = Parallel.run ~domains (fun () ->
      Ops.triangulate_2d ~grain:1 ~projection:Ops.Triangulate_2d_xy
        ~constraint_primitives:boundary ~ignore_non_constraint_points:true
        ~constraint_group:"boundary" input |> get) in
  let ignored = run 1 and parallel = run 4 in
  check (Geometry.point_count ignored = 5 && Geometry.primitive_count ignored = 2)
    "Ignore Non-Constraint Points cardinality";
  check (topology_signature ignored = topology_signature parallel)
    "Ignore Non-Constraint Points differs across domains";
  let view = Topology.Private.view (Geometry.topology ignored) in
  check (Array.for_all (fun point -> point <> 4) view.vertex_points)
    "ignored interior point entered output topology";
  (match Geometry.find_edge_group "boundary" ignored with
   | Some group -> check (Edge_group.cardinality group = 4)
       "Ignore Non-Constraint Points lost constraint edges"
   | None -> fail "Ignore Non-Constraint Points boundary group is missing");
  let compacted = Ops.triangulate_2d ~grain:1
      ~projection:Ops.Triangulate_2d_xy ~constraint_primitives:boundary
      ~ignore_non_constraint_points:true ~remove_unused_points:true
      ~recompute_point_normals:true input |> get in
  check (Geometry.point_count compacted = 4)
    "Triangulate 2D unused-point compaction cardinality";
  (match Geometry.find_attribute ~owner:Attribute.Point "N" compacted with
   | Some attribute ->
       (match Attribute.Private.storage attribute with
        | Attribute.Float3 values ->
            let values = Packed.Float3.Private.view values in
            check (Array.for_all ((=) 0.) values.x
                && Array.for_all ((=) 0.) values.y
                && Array.for_all ((=) 1.) values.z)
              "Triangulate 2D point normals were not recomputed"
        | _ -> fail "Triangulate 2D recomputed N changed storage")
   | None -> fail "Triangulate 2D did not recompute existing point N");
  (match Ops.triangulate_2d ~projection:Ops.Triangulate_2d_xy
      ~ignore_non_constraint_points:true (Ops.points
        [|0.,0.,0.;1.,0.,0.;0.,1.,0.|]) with
   | Error _ -> ()
   | Ok _ -> fail "Ignore Non-Constraint Points succeeded without constraints")

let test_remove_duplicate_points () =
  let input = Ops.points
      [|0.,0.,0.; 1.,0.,0.; 1.,1.,0.; 0.,1.,0.; 0.,0.,7.; 9.,9.,9.|] in
  let id = Attribute.create_owned ~name:"id" ~owner:Attribute.Point
      (Attribute.Int [|10;11;12;13;14;15|]) |> Result.get_ok in
  let selected = Group.ordered ~owner:Group.Point ~name:"selected" ~length:6
      [|0;1;2;3;4|] |> Result.get_ok
  and markers = Group.init ~owner:Group.Point ~name:"markers" 6
      (fun point -> point = 4 || point = 5) in
  let input = Geometry.with_attribute id input |> Result.get_ok
      |> Geometry.with_group selected |> Result.get_ok
      |> Geometry.with_group markers |> Result.get_ok in
  let ordinary = Ops.triangulate_2d ~projection:Ops.Triangulate_2d_xy
      ~selection:(Ops.Selected_points selected) input |> get in
  check (Geometry.point_count ordinary = 6)
    "projected duplicate was removed without the output policy";
  let run domains = Parallel.run ~domains (fun () ->
      Ops.triangulate_2d ~grain:1 ~projection:Ops.Triangulate_2d_xy
        ~selection:(Ops.Selected_points selected) ~remove_duplicate_points:true
        input |> get) in
  let output = run 1 and parallel = run 4 in
  check (Geometry.point_count output = 5 && Geometry.primitive_count output = 2)
    "projected duplicate removal cardinality";
  check (topology_signature output = topology_signature parallel)
    "projected duplicate removal topology differs across domains";
  let positions = Packed.Float3.Private.view (Geometry.positions output) in
  check (positions.x = [|0.;1.;1.;0.;9.|]
      && positions.y = [|0.;0.;1.;1.;9.|]
      && positions.z = [|0.;0.;0.;0.;9.|])
    "projected duplicate removal deleted or reordered an unrelated point";
  (match Geometry.find_attribute ~owner:Attribute.Point "id" output with
   | Some attribute ->
       (match Attribute.Private.storage attribute with
        | Attribute.Int values ->
            check (values = [|10;11;12;13;15|])
              "projected duplicate point attribute remap"
        | _ -> fail "projected duplicate point attribute changed storage")
   | None -> fail "projected duplicate removal dropped point payload");
  (match Geometry.find_group ~owner:Group.Point "selected" output with
   | Some group -> check (Group.cardinality group = 4 && not (Group.mem 4 group))
       "projected duplicate selection group remap"
   | None -> fail "projected duplicate removal dropped selection group");
  (match Geometry.find_group ~owner:Group.Point "markers" output with
   | Some group -> check (Group.cardinality group = 1 && Group.mem 4 group)
       "projected duplicate removal lost unrelated group membership"
   | None -> fail "projected duplicate removal dropped marker group")

let test_quality_refinement () =
  let input = Ops.points [|0.,0.,0.;2.,0.,2.;2.,2.,6.;0.,2.,4.|] in
  let value = Attribute.create_owned ~name:"value" ~owner:Attribute.Point
      (Attribute.Float [|0.;2.;6.;4.|]) |> Result.get_ok in
  let input = Geometry.with_attribute value input |> Result.get_ok in
  let run domains = Parallel.run ~domains (fun () ->
      Ops.triangulate_2d ~grain:1 ~projection:Ops.Triangulate_2d_xy
        ~refine:true ~maximum_area:0.3 ~maximum_new_points:100
        ~refinement_point_group:"refined" input |> get) in
  let output = run 1 and parallel = run 4 in
  check (Geometry.point_count output > 4 && Geometry.point_count output <= 104)
    "quality refinement point budget";
  let output_positions = Packed.Float3.Private.view (Geometry.positions output)
  and parallel_positions = Packed.Float3.Private.view (Geometry.positions parallel) in
  check (topology_signature output = topology_signature parallel
      && output_positions.x = parallel_positions.x
      && output_positions.y = parallel_positions.y
      && output_positions.z = parallel_positions.z)
    "quality refinement differs across domains";
  (match Geometry.find_group ~owner:Group.Point "refined" output with
   | Some group -> check (Group.cardinality group = Geometry.point_count output - 4)
       "quality refinement output group"
   | None -> fail "quality refinement point group is missing");
  let positions = output_positions in
  (match Geometry.find_attribute ~owner:Attribute.Point "value" output with
   | Some attribute ->
       (match Attribute.Private.storage attribute with
        | Attribute.Float values ->
            for point = 0 to Geometry.point_count output - 1 do
              check (abs_float (positions.z.(point) -. values.(point)) < 1e-10)
                "quality refinement payload interpolation"
            done
        | _ -> fail "quality refinement payload storage changed")
   | None -> fail "quality refinement payload is missing");
  let topology = Topology.Private.view (Geometry.topology output) in
  for primitive = 0 to Geometry.primitive_count output - 1 do
    let first = topology.primitive_offsets.(primitive) in
    let a = topology.vertex_points.(first)
    and b = topology.vertex_points.(first + 1)
    and c = topology.vertex_points.(first + 2) in
    let twice_area = abs_float
        (((positions.x.(b) -. positions.x.(a))
            *. (positions.y.(c) -. positions.y.(a)))
         -. ((positions.y.(b) -. positions.y.(a))
            *. (positions.x.(c) -. positions.x.(a)))) in
    check (0.5 *. twice_area <= 0.3 +. 1e-12)
      "quality refinement maximum area"
  done;
  let constrained_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;4.;2.|] ~y:[|0.;0.;0.2|] ~z:[|0.;8.;9.|] in
  let constrained_topology = Topology.create_owned ~point_count:3
      ~vertex_points:[|0;1|] ~primitive_offsets:[|0;2|]
      ~primitive_kinds:[|Topology.Open_polyline|] |> Result.get_ok in
  let constrained = Geometry.create ~positions:constrained_positions
      ~topology:constrained_topology () |> Result.get_ok in
  let constraint_primitives = Group.init ~owner:Group.Primitive
      ~name:"base" 1 (fun _ -> true) in
  let split = Ops.triangulate_2d ~grain:1 ~projection:Ops.Triangulate_2d_xy
      ~constraint_primitives ~refine:true ~minimum_angle:(Float.pi /. 6.)
      ~maximum_new_points:1 ~allow_constraint_splitting:true
      ~refinement_point_group:"refined" ~constraint_group:"constraints"
      constrained |> get in
  check (Geometry.point_count split = 4)
    "constraint refinement point cardinality";
  let split_positions = Packed.Float3.Private.view (Geometry.positions split) in
  check (split_positions.x.(3) = 2. && split_positions.y.(3) = 0.
      && split_positions.z.(3) = 4.)
    "constraint refinement midpoint interpolation";
  (match Geometry.find_edge_group "constraints" split with
   | Some group -> check (Edge_group.cardinality group = 2)
       "constraint refinement did not split the protected edge"
   | None -> fail "constraint refinement edge group is missing");
  let boundary_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;2.;2.;0.|] ~y:[|0.;0.;2.;2.|] ~z:[|0.;0.;0.;0.|] in
  let boundary_topology = Topology.polygons_owned ~point_count:4
      ~vertex_points:[|0;1;2;3|] ~primitive_offsets:[|0;4|]
      |> Result.get_ok in
  let boundary_geometry = Geometry.create ~positions:boundary_positions
      ~topology:boundary_topology () |> Result.get_ok in
  let boundary_group = Group.init ~owner:Group.Primitive ~name:"boundary" 1
      (fun _ -> true) in
  let boundary_refined = Ops.triangulate_2d ~grain:1
      ~projection:Ops.Triangulate_2d_xy ~constraint_primitives:boundary_group
      ~ignore_non_constraint_points:true
      ~remove_outside_constraint_polygons:true ~refine:true
      ~minimum_angle:1e-6 ~maximum_area:0.3 ~maximum_new_points:64
      ~allow_constraint_splitting:true ~constraint_group:"constraints"
      boundary_geometry |> get in
  check (Geometry.primitive_count boundary_refined > 2)
    "constraint-splitting refinement lost a bounded polygon interior";
  let crossing_topology = Topology.create_owned ~point_count:4
      ~vertex_points:[|0;1;2;3; 0;2; 1;3|]
      ~primitive_offsets:[|0;4;6;8|]
      ~primitive_kinds:[|Topology.Polygon;Topology.Open_polyline;
        Topology.Open_polyline|] |> Result.get_ok in
  let crossing_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|20.;300.;300.;20.|] ~y:[|20.;20.;200.;200.|]
      ~z:[|0.;0.;0.;0.|] in
  let crossing_geometry = Geometry.create ~positions:crossing_positions
      ~topology:crossing_topology () |> Result.get_ok in
  let crossing_group = Group.init ~owner:Group.Primitive ~name:"all_constraints" 3
      (fun _ -> true) in
  Array.iter (fun maximum_new_points ->
    let refined = Ops.triangulate_2d ~grain:1
        ~projection:Ops.Triangulate_2d_xy
        ~constraint_primitives:crossing_group ~split_crossing_constraints:true
        ~flood_from_hull_boundary:true ~remove_outside_constraint_polygons:true
        ~silhouette_constraints:true ~remove_outside_silhouette:true
        ~ignore_non_constraint_points:true
        ~refine:true ~minimum_angle:(Float.pi /. 18.) ~maximum_area:1_500.
        ~maximum_new_points ~allow_constraint_splitting:true crossing_geometry
        |> get in
    check (Geometry.primitive_count refined > 0)
      (Printf.sprintf
        "multi-constraint refinement lost its interior at point budget %d"
        maximum_new_points)) [|1;2;4;8;16;32;64;96|];
  let unsplit = Ops.triangulate_2d ~grain:1
      ~projection:Ops.Triangulate_2d_xy ~constraint_primitives
      ~refine:true ~minimum_angle:(Float.pi /. 6.) ~maximum_new_points:1
      ~allow_constraint_splitting:false ~constraint_group:"constraints"
      constrained |> get in
  (match Geometry.find_edge_group "constraints" unsplit with
   | Some group -> check (Edge_group.cardinality group = 1)
       "disabled constraint splitting changed the protected edge"
   | None -> fail "unsplit refinement constraint group is missing");
  let targeted = Ops.triangulate_2d ~grain:1
      ~projection:Ops.Triangulate_2d_xy ~refine:true ~minimum_angle:1e-6
      ~target_edge_length:0.75 ~maximum_new_points:100 input |> get in
  let targeted_positions = Packed.Float3.Private.view
      (Geometry.positions targeted) in
  let targeted_index = Topology_index.create (Geometry.topology targeted)
      |> Topology_index.Private.view in
  for edge = 0 to Array.length targeted_index.edge_a - 1 do
    let a = targeted_index.edge_a.(edge) and b = targeted_index.edge_b.(edge) in
    let dx = targeted_positions.x.(b) -. targeted_positions.x.(a)
    and dy = targeted_positions.y.(b) -. targeted_positions.y.(a) in
    check (sqrt ((dx *. dx) +. (dy *. dy)) <= 0.75 +. 1e-12)
      "quality refinement target edge length"
  done;
  let stopped = Ops.triangulate_2d ~projection:Ops.Triangulate_2d_xy
      ~refine:true ~maximum_area:0.01 ~maximum_new_points:0 input |> get in
  check (Geometry.point_count stopped = 4)
    "zero refinement point budget was not respected";
  let edge_limited = Ops.triangulate_2d ~projection:Ops.Triangulate_2d_xy
      ~refine:true ~maximum_area:0.01 ~minimum_edge_length:10.
      ~maximum_new_points:100 input |> get in
  check (Geometry.point_count edge_limited = 4)
    "minimum refinement edge length was not respected";
  let irregular = Ops.points
      [|0.,0.,0.; 3.,0.,3.; 2.,2.,6.; 0.,1.,2.|] in
  let run_regularized domains = Parallel.run ~domains (fun () ->
      Ops.triangulate_2d ~grain:1 ~projection:Ops.Triangulate_2d_xy
        ~refine:true ~minimum_angle:1e-6 ~maximum_area:0.2
        ~maximum_new_points:64 ~regularization_steps:2 irregular |> get) in
  let unregularized = Ops.triangulate_2d ~grain:1
      ~projection:Ops.Triangulate_2d_xy ~refine:true ~minimum_angle:1e-6
      ~maximum_area:0.2 ~maximum_new_points:64 irregular |> get in
  let regularized = run_regularized 1 and regularized_parallel = run_regularized 4 in
  let regularized_positions = Packed.Float3.Private.view
      (Geometry.positions regularized)
  and parallel_positions = Packed.Float3.Private.view
      (Geometry.positions regularized_parallel)
  and unregularized_positions = Packed.Float3.Private.view
      (Geometry.positions unregularized) in
  check (topology_signature regularized = topology_signature regularized_parallel
      && regularized_positions.x = parallel_positions.x
      && regularized_positions.y = parallel_positions.y
      && regularized_positions.z = parallel_positions.z)
    "quality regularization differs across domains";
  let moved = ref false in
  for point = 4 to Geometry.point_count regularized - 1 do
    if regularized_positions.x.(point) <> unregularized_positions.x.(point)
        || regularized_positions.y.(point) <> unregularized_positions.y.(point)
    then moved := true;
    check (abs_float (regularized_positions.z.(point)
        -. (regularized_positions.x.(point)
          +. (2. *. regularized_positions.y.(point)))) < 1e-9)
      "regularization provenance lost linear 3D payload"
  done;
  check !moved "quality regularization did not move any generated interior point";
  let movable_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;2.;2.;0.;0.2|] ~y:[|0.;0.;2.;2.;0.3|]
      ~z:[|0.;2.;6.;4.;0.8|] in
  let movable_topology = Topology.polygons_owned ~point_count:5
      ~vertex_points:[|0;1;2;3|] ~primitive_offsets:[|0;4|] |> Result.get_ok in
  let movable = Geometry.create ~positions:movable_positions
      ~topology:movable_topology () |> Result.get_ok in
  let movable_boundary = Group.init ~owner:Group.Primitive ~name:"boundary" 1
      (fun _ -> true) in
  let move_input domains = Parallel.run ~domains (fun () ->
      Ops.triangulate_2d ~grain:1 ~projection:Ops.Triangulate_2d_xy
        ~constraint_primitives:movable_boundary
        ~remove_outside_constraint_polygons:true ~refine:true
        ~minimum_angle:1e-6 ~maximum_new_points:0 ~regularization_steps:2
        ~allow_movement_of_interior_input_points:true
        ~constraint_group:"boundary" movable |> get) in
  let moved_one = move_input 1 and moved_four = move_input 4 in
  check (topology_signature moved_one = topology_signature moved_four
      && Geometry.point_count moved_one = 5)
    "input-point regularization differs across domains";
  (match Geometry.find_edge_group "boundary" moved_one with
   | Some group -> check (Edge_group.cardinality group = 4)
       "input-point regularization moved or lost a protected boundary"
   | None -> fail "input-point regularization boundary group is missing")

let test_projected_silhouette () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|-2.;2.;2.;-2.; -1.;1.;1.;-1.;0.|]
      ~y:[|-2.;-2.;2.;2.; -1.;-1.;1.;1.;0.|]
      ~z:[|0.;0.;0.;0.;0.;0.;0.;0.;0.|] in
  let topology = Topology.polygons_owned ~point_count:9
      ~vertex_points:[|4;5;6; 4;6;7|] ~primitive_offsets:[|0;3;6|]
      |> Result.get_ok in
  let input = Geometry.create ~positions ~topology () |> Result.get_ok in
  let constrained = Ops.triangulate_2d ~grain:1
      ~projection:Ops.Triangulate_2d_xy ~silhouette_constraints:true
      ~constraint_group:"silhouette" input |> get in
  (match Geometry.find_edge_group "silhouette" constrained with
   | Some group -> check (Edge_group.cardinality group = 4)
       "silhouette retained an internal same-facing edge"
   | None -> fail "silhouette constraint group is missing");
  let run domains = Parallel.run ~domains (fun () ->
      Ops.triangulate_2d ~grain:1 ~projection:Ops.Triangulate_2d_xy
        ~remove_outside_silhouette:true ~constraint_group:"silhouette" input
      |> get) in
  let output = run 1 and parallel = run 4 in
  check (topology_signature output = topology_signature parallel)
    "silhouette one/four-domain topology differs";
  check (Geometry.primitive_count output = 4)
    "silhouette removal retained the wrong triangle count";
  let view = Topology.Private.view (Geometry.topology output) in
  check (Array.for_all (fun point -> point >= 4) view.vertex_points)
    "silhouette removal retained an exterior point";
  let reversed_topology = Topology.polygons_owned ~point_count:9
      ~vertex_points:[|6;5;4; 7;6;4|] ~primitive_offsets:[|0;3;6|]
      |> Result.get_ok in
  let reversed = Geometry.create ~positions ~topology:reversed_topology ()
      |> Result.get_ok |> Ops.triangulate_2d
          ~projection:Ops.Triangulate_2d_xy
          ~remove_outside_silhouette:true |> get in
  check (topology_signature reversed = topology_signature output)
    "silhouette removal depends on global face orientation";
  let partial = Group.init ~owner:Group.Point ~name:"partial" 9
      (fun point -> point = 4 || point = 5 || point = 7) in
  (match Ops.triangulate_2d ~projection:Ops.Triangulate_2d_xy
      ~selection:(Ops.Selected_points partial) ~silhouette_constraints:true input with
   | Error _ -> ()
   | Ok _ -> fail "silhouette accepted a partially selected polygon");
  let flat_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;2.;0.;2.|] ~y:[|0.;0.;0.;1.;1.|]
      ~z:[|0.;0.;0.;0.;0.|] in
  let flat_topology = Topology.polygons_owned ~point_count:5
      ~vertex_points:[|0;1;2|] ~primitive_offsets:[|0;3|]
      |> Result.get_ok in
  let flat = Geometry.create ~positions:flat_positions ~topology:flat_topology ()
      |> Result.get_ok |> Ops.triangulate_2d
          ~projection:Ops.Triangulate_2d_xy
          ~remove_outside_silhouette:true |> get in
  check (Geometry.primitive_count flat = 0)
    "zero-area projected silhouette invented an interior"

let test_domain_exactness () =
  let count = 2_000 in
  let input = Ops.points (Array.init count (fun point ->
      let x = float_of_int ((point * 7919) mod 2003) in
      let y = float_of_int ((point * 3571) mod 2011) +. (float_of_int point *. 1e-8) in
      x,y,(x *. 0.25) -. (y *. 0.125))) in
  let run domains = Parallel.run ~domains (fun () ->
      Ops.triangulate_2d ~grain:31 input |> get |> topology_signature) in
  check (run 1 = run 4) "one/four-domain topology differs"

let test_errors () =
  let input = Ops.points [|0.,0.,0.; 1.,0.,0.; 0.,1.,0.|] in
  let expect = function Error _ -> () | Ok _ -> fail "invalid input succeeded" in
  expect (Ops.triangulate_2d
      ~projection:(Ops.Triangulate_2d_plane {
        origin = Vec3.zero; normal = Vec3.zero }) input);
  expect (Ops.triangulate_2d
      ~projection:(Ops.Triangulate_2d_point_attribute "missing") input);
  expect (Ops.triangulate_2d ~refine:true ~minimum_angle:(Float.pi /. 3.) input);
  expect (Ops.triangulate_2d ~refine:true ~maximum_area:0. input);
  expect (Ops.triangulate_2d ~refine:true ~target_edge_length:nan input);
  expect (Ops.triangulate_2d ~refine:true ~minimum_edge_length:(-1.) input);
  expect (Ops.triangulate_2d ~refine:true ~maximum_new_points:(-1) input);
  expect (Ops.triangulate_2d ~refine:true ~regularization_steps:(-1) input);
  expect (Ops.triangulate_2d ~refinement_point_group:" " input);
  let cancel = Cancel.create () in Cancel.cancel cancel;
  expect (Ops.triangulate_2d ~cancel input);
  expect (Ops.triangulate_2d ~cancel ~refine:true
      ~maximum_area:0.01 input)

let () =
  test_xy_payload_and_group ();
  test_best_fit_and_explicit_plane ();
  test_attribute_and_selection ();
  test_constraints ();
  test_crossing_constraints_and_payload ();
  test_hull_boundary_flood ();
  test_ignore_non_constraint_points ();
  test_remove_duplicate_points ();
  test_quality_refinement ();
  test_projected_silhouette ();
  test_domain_exactness ();
  test_errors ()
