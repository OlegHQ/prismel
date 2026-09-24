open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function
  | Ok value -> value
  | Error error -> fail (Error.to_string error)

let geometry point_count faces =
  let positions = Packed.Float3.Builder.create point_count in
  for point = 0 to point_count - 1 do
    Packed.Float3.Builder.set positions point (float_of_int point) 0. 0.
  done;
  let topology = Topology.Builder.create ~point_count () in
  Array.iter (Topology.Builder.add_polygon topology) faces;
  Geometry.create ~positions:(Packed.Float3.Builder.freeze positions)
    ~topology:(Topology.Builder.freeze topology) ()
  |> function Ok geometry -> geometry | Error message -> fail message

let two_quads () = geometry 6 [|[|0; 1; 4; 3|]; [|1; 2; 5; 4|]|]

let owner_count geometry = function
  | Group.Point -> Geometry.point_count geometry
  | Group.Vertex -> Geometry.vertex_count geometry
  | Group.Primitive -> Geometry.primitive_count geometry

let with_group owner name predicate geometry =
  Geometry.with_group (Group.init ~grain:1 ~owner ~name
      (owner_count geometry owner) predicate) geometry
  |> function Ok geometry -> geometry | Error message -> fail message

let with_int owner name values geometry =
  let attribute = Attribute.create_owned ~owner ~name (Attribute.Int values)
      |> function Ok value -> value | Error message -> fail message in
  Geometry.with_attribute attribute geometry
  |> function Ok geometry -> geometry | Error message -> fail message

let group owner name geometry = match Geometry.find_group ~owner name geometry with
  | Some group -> group
  | None -> fail ("missing group " ^ name)

let edge_group name geometry = match Geometry.find_edge_group name geometry with
  | Some group -> group
  | None -> fail ("missing edge group " ^ name)

let int_attribute owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Int values -> values
       | _ -> fail ("non-integer attribute " ^ name))
  | None -> fail ("missing attribute " ^ name)

let promote ?name ?keep_original ?output_attribute ?attributes ?tolerance
    ?include_unshared_edges ?include_all_unshared_curve_edges
    ?include_all_primitives_sharing_boundary_points
    ~source ~destination ~group geometry =
  Ops.group_promote_boundary ~grain:1 ?name ?keep_original ?output_attribute
    ?attributes ?tolerance ?include_unshared_edges
    ?include_all_unshared_curve_edges
    ?include_all_primitives_sharing_boundary_points
    ~source ~destination ~group geometry |> get_ok

let test_primitive_boundary () =
  let source = two_quads ()
      |> with_group Group.Primitive "first" (fun primitive -> primitive = 0) in
  let shared = promote ~keep_original:true ~name:"shared"
      ~source:Ops.Group_primitives ~destination:Ops.Group_edges ~group:"first"
      source in
  check (Edge_group.cardinality (edge_group "shared" shared) = 1)
    "Group Promote Boundary did not remove primitive interior/unshared edges";
  let complete = promote ~keep_original:true ~name:"complete"
      ~include_unshared_edges:true ~source:Ops.Group_primitives
      ~destination:Ops.Group_edges ~group:"first" source in
  check (Edge_group.cardinality (edge_group "complete" complete) = 4)
    "Group Promote Boundary did not include selected polygon unshared edges";
  let points = promote ~keep_original:true ~name:"boundary_points"
      ~source:Ops.Group_primitives ~destination:Ops.Group_points ~group:"first"
      source in
  let points = group Group.Point "boundary_points" points in
  check (Group.cardinality points = 2 && Group.mem 1 points && Group.mem 4 points)
    "Group Promote Boundary point output crossed the selected side";
  let mask = promote ~keep_original:true ~output_attribute:"boundary_mask"
      ~source:Ops.Group_primitives ~destination:Ops.Group_points ~group:"first"
      source in
  check (int_attribute Attribute.Point "boundary_mask" mask
      = [|0; 1; 0; 0; 1; 0|])
    "Group Promote Boundary integer output"

let test_point_vertex_and_edge_sources () =
  let base = two_quads () in
  let point_source = with_group Group.Point "left"
      (fun point -> point = 0 || point = 3) base in
  let edges = promote ~keep_original:true ~name:"point_cut"
      ~source:Ops.Group_points ~destination:Ops.Group_edges ~group:"left"
      point_source in
  check (Edge_group.cardinality (edge_group "point_cut" edges) = 2)
    "Group Promote Boundary point-to-edge cut";
  let vertices = with_group Group.Vertex "first_corners"
      (fun vertex -> vertex < 4) base in
  let vertex_boundary = promote ~keep_original:true ~name:"corner_boundary"
      ~source:Ops.Group_vertices ~destination:Ops.Group_vertices
      ~group:"first_corners" vertices in
  check (Group.cardinality
      (group Group.Vertex "corner_boundary" vertex_boundary) = 2)
    "Group Promote Boundary vertex topology";
  let index = Topology_index.create (Geometry.topology base) in
  let shared = Option.get (Topology_index.find_edge index ~a:1 ~b:4) in
  let selected = Edge_group.init ~grain:1 ~topology:(Geometry.topology base)
      ~index ~name:"explicit_edge" (fun edge -> edge = shared) in
  let edge_source = Geometry.with_edge_group selected base
      |> function Ok value -> value | Error message -> fail message in
  let primitives = promote ~keep_original:true ~name:"edge_faces"
      ~source:Ops.Group_edges ~destination:Ops.Group_primitives
      ~group:"explicit_edge" edge_source in
  check (Group.cardinality (group Group.Primitive "edge_faces" primitives) = 2)
    "Group Promote Boundary explicit edge source"

let test_all_owner_pairs () =
  let base = two_quads () in
  let index = Topology_index.create (Geometry.topology base) in
  let shared = Option.get (Topology_index.find_edge index ~a:1 ~b:4) in
  let edge_source = Edge_group.init ~grain:1 ~topology:(Geometry.topology base)
      ~index ~name:"source" (fun edge -> edge = shared) in
  let sources = [
    Ops.Group_points,
      with_group Group.Point "source" (fun point -> point = 0 || point = 1) base,
      [|2; 3; 2; 3|];
    Ops.Group_vertices,
      with_group Group.Vertex "source" (fun vertex -> vertex = 0 || vertex = 1)
        base,
      [|1; 1; 1; 1|];
    Ops.Group_primitives,
      with_group Group.Primitive "source" (fun primitive -> primitive = 0) base,
      [|2; 2; 1; 1|];
    Ops.Group_edges,
      (Geometry.with_edge_group edge_source base
       |> function Ok value -> value | Error message -> fail message),
      [|2; 4; 2; 1|]
  ] in
  let destinations = [|Ops.Group_points; Ops.Group_vertices;
    Ops.Group_primitives; Ops.Group_edges|] in
  List.iter (fun (source_owner, source, expected) ->
    Array.iteri (fun destination_index destination ->
      let output = promote ~keep_original:true ~name:"output"
          ~source:source_owner ~destination ~group:"source" source in
      let cardinality = match destination with
        | Ops.Group_points -> Group.cardinality
            (group Group.Point "output" output)
        | Ops.Group_vertices -> Group.cardinality
            (group Group.Vertex "output" output)
        | Ops.Group_primitives -> Group.cardinality
            (group Group.Primitive "output" output)
        | Ops.Group_edges -> Edge_group.cardinality (edge_group "output" output) in
      check (cardinality = expected.(destination_index))
        (Printf.sprintf "Group Promote Boundary owner pair %d -> %d"
          (match source_owner with Ops.Group_points -> 0 | Ops.Group_vertices -> 1
            | Ops.Group_primitives -> 2 | Ops.Group_edges -> 3)
          destination_index)) destinations) sources

let test_curve_unshared_policy () =
  let positions = [|(0., 0., 0.); (1., 0., 0.); (2., 0., 0.);
    (3., 0., 0.)|] in
  let geometry = Ops.polyline ~closed:false positions |> get_ok
      |> with_group Group.Primitive "curve" (fun _ -> true) in
  let ends = promote ~keep_original:true ~include_unshared_edges:true
      ~name:"ends" ~source:Ops.Group_primitives ~destination:Ops.Group_edges
      ~group:"curve" geometry
  and all = promote ~keep_original:true ~include_unshared_edges:true
      ~include_all_unshared_curve_edges:true ~name:"all"
      ~source:Ops.Group_primitives ~destination:Ops.Group_edges
      ~group:"curve" geometry in
  check (Edge_group.cardinality (edge_group "ends" ends) = 2)
    "Group Promote Boundary open-curve endpoint policy";
  check (Edge_group.cardinality (edge_group "all" all) = 3)
    "Group Promote Boundary all open-curve edges policy"

let test_attribute_boundary_and_point_sharing () =
  let source = two_quads ()
      |> with_group Group.Primitive "all" (fun _ -> true)
      |> with_int Attribute.Primitive "material" [|0; 1|] in
  let attributes = [{ Ops.boundary_attribute_owner = Attribute.Primitive;
    boundary_attribute_pattern = "material" }] in
  let seam = promote ~keep_original:true ~attributes ~name:"material_seam"
      ~source:Ops.Group_primitives ~destination:Ops.Group_edges ~group:"all"
      source in
  check (Edge_group.cardinality (edge_group "material_seam" seam) = 1)
    "Group Promote Boundary did not union an attribute seam";
  let fan = geometry 6 [|
      [|0; 1; 2|]; [|1; 3; 2|]; [|1; 4; 5|]
    |]
      |> with_group Group.Primitive "all" (fun _ -> true)
      |> with_int Attribute.Primitive "piece" [|0; 1; 0|] in
  let attributes = [{ Ops.boundary_attribute_owner = Attribute.Primitive;
    boundary_attribute_pattern = "piece" }] in
  let edge_only = promote ~keep_original:true ~attributes ~name:"edge_faces"
      ~source:Ops.Group_primitives ~destination:Ops.Group_primitives ~group:"all"
      fan
  and point_touching = promote ~keep_original:true ~attributes
      ~include_all_primitives_sharing_boundary_points:true ~name:"point_faces"
      ~source:Ops.Group_primitives ~destination:Ops.Group_primitives ~group:"all"
      fan in
  check (Group.cardinality (group Group.Primitive "edge_faces" edge_only) = 2)
    "Group Promote Boundary primitive edge incidence";
  check (Group.cardinality
      (group Group.Primitive "point_faces" point_touching) = 3)
    "Group Promote Boundary primitive point-sharing expansion"

let test_validation_and_lifecycle () =
  let source = two_quads ()
      |> with_group Group.Primitive "first" (fun primitive -> primitive = 0) in
  let replaced = promote ~name:"outline" ~source:Ops.Group_primitives
      ~destination:Ops.Group_edges ~group:"first" source in
  check (Geometry.find_group ~owner:Group.Primitive "first" replaced = None
      && Geometry.find_edge_group "outline" replaced <> None)
    "Group Promote Boundary source removal/output rename";
  (match Ops.group_promote_boundary
      ~include_all_primitives_sharing_boundary_points:true
      ~source:Ops.Group_primitives ~destination:Ops.Group_points
      ~group:"first" source with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Promote Boundary invalid point-sharing owner code"
   | Ok _ -> fail "Group Promote Boundary accepted point sharing for points");
  (match Ops.group_promote_boundary ~include_all_unshared_curve_edges:true
      ~source:Ops.Group_primitives ~destination:Ops.Group_edges
      ~group:"first" source with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Promote Boundary curve-policy validation code"
   | Ok _ -> fail "Group Promote Boundary accepted curve edges without unshared");
  (match Ops.group_promote_boundary ~tolerance:nan
      ~source:Ops.Group_primitives ~destination:Ops.Group_edges
      ~group:"first" source with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Promote Boundary non-finite tolerance code"
   | Ok _ -> fail "Group Promote Boundary accepted a non-finite tolerance");
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.group_promote_boundary ~cancel:cancelled
      ~source:Ops.Group_primitives ~destination:Ops.Group_edges
      ~group:"first" source with
   | Error error -> check (Error.code error = "cancelled")
       "Group Promote Boundary cancellation code"
   | Ok _ -> fail "cancelled Group Promote Boundary published geometry")

let same_group left right =
  Bytes.equal (Group.Private.bits_view left) (Group.Private.bits_view right)

let same_edge_group left right =
  Edge_group.length left = Edge_group.length right
  && let equal = ref true in
     for edge = 0 to Edge_group.length left - 1 do
       if Edge_group.mem edge left <> Edge_group.mem edge right then equal := false
     done;
     !equal

let test_parallel_exactness () =
  let base = Ops.grid ~columns:600 ~rows:400 ~size:20. () |> get_ok in
  let source = with_group Group.Primitive "left_half"
      (fun primitive -> primitive mod 1_200 < 600) base in
  let run domains = Parallel.run ~domains (fun () ->
    source
    |> Ops.group_promote_boundary ~grain:1_009 ~keep_original:true
         ~include_unshared_edges:true ~name:"outline"
         ~source:Ops.Group_primitives ~destination:Ops.Group_edges
         ~group:"left_half" |> get_ok
    |> Ops.group_promote_boundary ~grain:1_009 ~keep_original:true
         ~include_unshared_edges:true ~name:"outline_points"
         ~source:Ops.Group_primitives ~destination:Ops.Group_points
         ~group:"left_half" |> get_ok) in
  let one = run 1 and four = run 4 in
  check (same_edge_group (edge_group "outline" one) (edge_group "outline" four))
    "Group Promote Boundary edge output differs by domain count";
  check (same_group (group Group.Point "outline_points" one)
      (group Group.Point "outline_points" four))
    "Group Promote Boundary point output differs by domain count"

let () =
  test_primitive_boundary ();
  test_point_vertex_and_edge_sources ();
  test_all_owner_pairs ();
  test_curve_unshared_policy ();
  test_attribute_boundary_and_point_sharing ();
  test_validation_and_lifecycle ();
  test_parallel_exactness ();
  print_endline "group promote boundary tests passed"
