open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function
  | Ok value -> value
  | Error error -> fail (Error.to_string error)

let geometry positions add_primitives =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:(Array.map (fun (x, _, _) -> x) positions)
      ~y:(Array.map (fun (_, y, _) -> y) positions)
      ~z:(Array.map (fun (_, _, z) -> z) positions) in
  let topology = Topology.Builder.create ~point_count:(Packed.Float3.length positions) () in
  add_primitives topology;
  Geometry.create ~positions ~topology:(Topology.Builder.freeze topology) ()
  |> function Ok value -> value | Error message -> fail message

let two_quads () = geometry
    [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.);
      (0.,1.,0.); (1.,1.,0.); (2.,1.,0.)|]
    (fun topology ->
      Topology.Builder.add_polygon topology [|0;1;4;3|];
      Topology.Builder.add_polygon topology [|1;2;5;4|])

let open_curve () = geometry
    [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.); (3.,0.,0.)|]
    (fun topology -> Topology.Builder.add_open_polyline topology [|0;1;2;3|])

let with_attribute owner name storage geometry =
  let attribute = Attribute.create_owned ~owner ~name storage
      |> function Ok value -> value | Error message -> fail message in
  Geometry.with_attribute attribute geometry
  |> function Ok value -> value | Error message -> fail message

let rule owner pattern = {
  Group_ops.boundary_attribute_owner = owner;
  boundary_attribute_pattern = pattern;
}

let edge_group name geometry = Geometry.find_edge_group name geometry |> Option.get
let group owner name geometry = Geometry.find_group ~owner name geometry |> Option.get

let selected_edge geometry group a b =
  let index = Topology_index.create (Geometry.topology geometry) in
  match Topology_index.find_edge index ~a ~b with
  | Some edge -> Edge_group.mem edge group
  | None -> fail (Printf.sprintf "missing fixture edge %d-%d" a b)

let members group =
  let result = ref [] in
  Group.iter (fun element -> result := element :: !result) group;
  List.rev !result

let same_edges left right =
  Edge_group.length left = Edge_group.length right
  && begin
    let equal = ref true in
    for edge = 0 to Edge_group.length left - 1 do
      if Edge_group.mem edge left <> Edge_group.mem edge right then equal := false
    done;
    !equal
  end

let test_primitive_boundaries_and_outputs () =
  let source = two_quads ()
      |> with_attribute Attribute.Primitive "material" (Attribute.Int [|2;7|]) in
  let attributes = [rule Attribute.Primitive "material"] in
  let edges = Group_ops.group_from_attribute_boundary ~grain:1 ~attributes
      ~owner:Group_ops.Group_edges ~name:"seams" source |> get_ok in
  let seams = edge_group "seams" edges in
  check (Edge_group.cardinality seams = 1 && selected_edge source seams 1 4)
    "primitive attribute discontinuity did not select the shared edge";
  let points = Group_ops.group_from_attribute_boundary ~grain:1 ~attributes
      ~owner:Group_ops.Group_points ~name:"seam_points" source |> get_ok in
  check (members (group Group.Point "seam_points" points) = [1;4])
    "edge boundary did not convert to its endpoint points";
  let primitives = Group_ops.group_from_attribute_boundary ~grain:1 ~attributes
      ~owner:Group_ops.Group_primitives ~name:"seam_faces" source |> get_ok in
  check (members (group Group.Primitive "seam_faces" primitives) = [0;1])
    "edge boundary did not convert to incident primitives"

let test_numeric_tolerance_and_patterns () =
  let source = two_quads ()
      |> with_attribute Attribute.Primitive "weight"
           (Attribute.Float [|1.; 1.0005|])
      |> with_attribute Attribute.Primitive "ignored"
           (Attribute.Int [|0;1|]) in
  let loose = Group_ops.group_from_attribute_boundary ~grain:1 ~tolerance:0.001
      ~attributes:[rule Attribute.Primitive "weight"]
      ~owner:Group_ops.Group_edges ~name:"loose" source |> get_ok in
  check (Edge_group.cardinality (edge_group "loose" loose) = 0)
    "float tolerance classified an equal primitive value";
  let strict = Group_ops.group_from_attribute_boundary ~grain:1 ~tolerance:0.0001
      ~attributes:[rule Attribute.Primitive "wei*"]
      ~owner:Group_ops.Group_edges ~name:"strict" source |> get_ok in
  check (Edge_group.cardinality (edge_group "strict" strict) = 1)
    "compiled attribute pattern or strict tuple tolerance failed"

let test_vertex_seam () =
  let source = two_quads () in
  let uv = Packed.Float2.of_owned
      ~x:[|0.;0.;0.;0.;1.;0.;0.;1.|]
      ~y:(Array.make 8 0.) |> function
    | Ok value -> value | Error message -> fail message in
  let source = with_attribute Attribute.Vertex "uv" (Attribute.Float2 uv) source in
  let output = Group_ops.group_from_attribute_boundary ~grain:1
      ~attributes:[rule Attribute.Vertex "uv"]
      ~owner:Group_ops.Group_edges ~name:"uv_seam" source |> get_ok in
  let seam = edge_group "uv_seam" output in
  check (Edge_group.cardinality seam = 1 && selected_edge source seam 1 4)
    "vertex endpoint comparison did not detect the shared-edge seam"

let test_storage_kinds_and_nonmanifold () =
  let text_source = two_quads ()
      |> with_attribute Attribute.Primitive "label"
           (Attribute.Text [|"left"; "right"|]) in
  let text_output = Group_ops.group_from_attribute_boundary ~grain:1
      ~attributes:[rule Attribute.Primitive "label"]
      ~owner:Group_ops.Group_edges ~name:"text_seam" text_source |> get_ok in
  check (Edge_group.cardinality (edge_group "text_seam" text_output) = 1)
    "text attribute boundary was not compared exactly";
  let triangle = geometry [|(0.,0.,0.); (1.,0.,0.); (0.,1.,0.)|]
      (fun topology -> Topology.Builder.add_triangle topology 0 1 2) in
  let weights = Packed.Float4.of_owned ~x:[|0.;0.;0.|] ~y:[|0.;0.;0.|]
      ~z:[|0.;0.;0.|] ~w:[|0.;0.;0.25|] |> function
    | Ok value -> value | Error message -> fail message in
  let tuple_source = with_attribute Attribute.Point "weights"
      (Attribute.Float4 weights) triangle in
  let tuple_output = Group_ops.group_from_attribute_boundary ~grain:1 ~tolerance:0.1
      ~attributes:[rule Attribute.Point "weights"]
      ~owner:Group_ops.Group_edges ~name:"tuple_seams" tuple_source |> get_ok in
  check (Edge_group.cardinality (edge_group "tuple_seams" tuple_output) = 2)
    "float4 component boundary did not use component-wise tolerance";
  let nonmanifold = geometry
      [|(0.,0.,0.); (1.,0.,0.); (0.,1.,0.); (0.,-1.,0.); (0.,0.,1.)|]
      (fun topology ->
        Topology.Builder.add_triangle topology 0 1 2;
        Topology.Builder.add_triangle topology 1 0 3;
        Topology.Builder.add_triangle topology 0 1 4)
      |> with_attribute Attribute.Primitive "piece" (Attribute.Int [|0;0;1|]) in
  let output = Group_ops.group_from_attribute_boundary ~grain:1
      ~attributes:[rule Attribute.Primitive "piece"]
      ~owner:Group_ops.Group_edges ~name:"nonmanifold_seam" nonmanifold |> get_ok in
  let seam = edge_group "nonmanifold_seam" output in
  check (Edge_group.cardinality seam = 1
      && selected_edge nonmanifold seam 0 1)
    "non-manifold incidence did not compare every primitive side"

let test_unshared_curve_policy () =
  let source = open_curve () in
  let endpoints = Group_ops.group_from_attribute_boundary ~grain:1
      ~include_unshared_edges:true ~owner:Group_ops.Group_edges ~name:"ends" source
      |> get_ok in
  check (Edge_group.cardinality (edge_group "ends" endpoints) = 2)
    "open curve endpoint policy did not select exactly first/last edges";
  let all = Group_ops.group_from_attribute_boundary ~grain:1
      ~include_unshared_edges:true ~include_all_unshared_curve_edges:true
      ~owner:Group_ops.Group_edges ~name:"all" source |> get_ok in
  check (Edge_group.cardinality (edge_group "all" all) = 3)
    "all-unshared-curve policy omitted curve edges";
  let polygon = Group_ops.group_from_attribute_boundary ~grain:1
      ~include_unshared_edges:true ~owner:Group_ops.Group_edges ~name:"boundary"
      (two_quads ()) |> get_ok in
  check (Edge_group.cardinality (edge_group "boundary" polygon) = 6)
    "polygon unshared policy included the shared edge or omitted a boundary"

let test_primitive_point_sharing_expansion () =
  let source = geometry
      [|(0.,0.,0.); (1.,0.,0.); (0.,1.,0.);
        (0.,-1.,0.); (-1.,1.,0.); (-1.,0.,0.)|]
      (fun topology ->
        Topology.Builder.add_triangle topology 0 1 2;
        Topology.Builder.add_triangle topology 1 0 3;
        Topology.Builder.add_triangle topology 0 4 5)
      |> with_attribute Attribute.Primitive "piece" (Attribute.Int [|0;1;0|]) in
  let attributes = [rule Attribute.Primitive "piece"] in
  let incident = Group_ops.group_from_attribute_boundary ~grain:1 ~attributes
      ~owner:Group_ops.Group_primitives ~name:"incident" source |> get_ok in
  check (members (group Group.Primitive "incident" incident) = [0;1])
    "default primitive conversion included a point-only neighbor";
  let expanded = Group_ops.group_from_attribute_boundary ~grain:1 ~attributes
      ~include_all_primitives_sharing_boundary_points:true
      ~owner:Group_ops.Group_primitives ~name:"expanded" source |> get_ok in
  check (members (group Group.Primitive "expanded" expanded) = [0;1;2])
    "point-sharing primitive expansion omitted an incident face"

let test_position_and_validation () =
  let triangle = geometry [|(0.,0.,0.); (1.,0.,0.); (0.,1.,0.)|]
      (fun topology -> Topology.Builder.add_triangle topology 0 1 2) in
  let position = Group_ops.group_from_attribute_boundary ~grain:1
      ~attributes:[rule Attribute.Point "P"]
      ~owner:Group_ops.Group_edges ~name:"position" triangle |> get_ok in
  check (Edge_group.cardinality (edge_group "position" position) = 3)
    "canonical P pattern was not treated as a point attribute";
  (match Group_ops.group_from_attribute_boundary
      ~attributes:[rule Attribute.Point "missing"]
      ~owner:Group_ops.Group_edges ~name:"bad" triangle with
   | Error error -> check (Error.code error = "invalid_group")
       "missing boundary attribute error code"
   | Ok _ -> fail "missing boundary attribute was accepted");
  (match Group_ops.group_from_attribute_boundary
      ~attributes:[rule Attribute.Detail "meta"]
      ~owner:Group_ops.Group_edges ~name:"bad" triangle with
   | Error _ -> () | Ok _ -> fail "detail boundary attribute was accepted");
  let nonfinite = two_quads ()
      |> with_attribute Attribute.Primitive "weight"
           (Attribute.Float [|0.; Float.nan|]) in
  (match Group_ops.group_from_attribute_boundary
      ~attributes:[rule Attribute.Primitive "weight"]
      ~owner:Group_ops.Group_edges ~name:"bad" nonfinite with
   | Error _ -> () | Ok _ -> fail "non-finite boundary attribute was accepted");
  let cancel = Cancel.create () in
  Cancel.cancel cancel;
  (match Group_ops.group_from_attribute_boundary ~cancel
      ~attributes:[rule Attribute.Point "P"]
      ~owner:Group_ops.Group_edges ~name:"bad" triangle with
   | Error error -> check (Error.code error = "cancelled")
       "cancelled boundary classification error code"
   | Ok _ -> fail "cancelled boundary classification published geometry")

let test_parallel_scale_exactness () =
  let source = Plane_generators.grid ~columns:120 ~rows:90 ~size:20. () |> get_ok in
  let primitive_count = Geometry.primitive_count source in
  let source = with_attribute Attribute.Primitive "face_id"
      (Attribute.Int (Array.init primitive_count Fun.id)) source in
  let run domains = Parallel.run ~domains (fun () ->
    Group_ops.group_from_attribute_boundary ~grain:257
      ~attributes:[rule Attribute.Primitive "face_id"]
      ~owner:Group_ops.Group_edges ~name:"all_internal" source |> get_ok) in
  let one = edge_group "all_internal" (run 1)
  and four = edge_group "all_internal" (run 4) in
  check (same_edges one four)
    "Group from Attribute Boundary one/four-domain output differs";
  check (Edge_group.cardinality one = (3 * 120 * 90) - 120 - 90)
    "Group from Attribute Boundary scale cardinality"

let run () =
  test_primitive_boundaries_and_outputs ();
  test_numeric_tolerance_and_patterns ();
  test_vertex_seam ();
  test_storage_kinds_and_nonmanifold ();
  test_unshared_curve_policy ();
  test_primitive_point_sharing_expansion ();
  test_position_and_validation ();
  test_parallel_scale_exactness ();
  print_endline "group attribute boundary tests passed"
