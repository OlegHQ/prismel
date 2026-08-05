open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function Ok value -> value | Error message -> fail message
let get_pdk = function
  | Ok value -> value
  | Error error -> fail (Error.to_string error)

let equal_storage left right =
  match Attribute.Private.storage left, Attribute.Private.storage right with
  | Attribute.Float left, Attribute.Float right -> left = right
  | Attribute.Int left, Attribute.Int right -> left = right
  | Attribute.Text left, Attribute.Text right -> left = right
  | Attribute.Float2 left, Attribute.Float2 right ->
      let left = Packed.Float2.Private.view left
      and right = Packed.Float2.Private.view right in
      left.x = right.x && left.y = right.y
  | Attribute.Float3 left, Attribute.Float3 right ->
      let left = Packed.Float3.Private.view left
      and right = Packed.Float3.Private.view right in
      left.x = right.x && left.y = right.y && left.z = right.z
  | Attribute.Float4 left, Attribute.Float4 right ->
      let left = Packed.Float4.Private.view left
      and right = Packed.Float4.Private.view right in
      left.x = right.x && left.y = right.y && left.z = right.z
      && left.w = right.w
  | Attribute.Int_array left, Attribute.Int_array right ->
      let left = Packed.Int_array.Private.view left
      and right = Packed.Int_array.Private.view right in
      left.offsets = right.offsets && left.values = right.values
  | Attribute.Float_array left, Attribute.Float_array right ->
      let left = Packed.Float_array.Private.view left
      and right = Packed.Float_array.Private.view right in
      left.offsets = right.offsets && left.values = right.values
  | _ -> false

let equal_group left right =
  Group.owner left = Group.owner right
  && String.equal (Group.name left) (Group.name right)
  && Group.length left = Group.length right
  && Group.ordered_elements left = Group.ordered_elements right
  && begin
    let same = ref true in
    for element = 0 to Group.length left - 1 do
      if Group.mem element left <> Group.mem element right then same := false
    done;
    !same
  end

let equal_edge_group left right =
  String.equal (Edge_group.name left) (Edge_group.name right)
  && Edge_group.length left = Edge_group.length right
  && begin
    let same = ref true in
    for edge = 0 to Edge_group.length left - 1 do
      if Edge_group.mem edge left <> Edge_group.mem edge right then same := false
    done;
    !same
  end

let equal_geometry left right =
  let left_positions = Packed.Float3.Private.view (Geometry.positions left)
  and right_positions = Packed.Float3.Private.view (Geometry.positions right)
  and left_topology = Topology.Private.view (Geometry.topology left)
  and right_topology = Topology.Private.view (Geometry.topology right) in
  left_positions.x = right_positions.x
  && left_positions.y = right_positions.y
  && left_positions.z = right_positions.z
  && left_topology.point_count = right_topology.point_count
  && left_topology.vertex_points = right_topology.vertex_points
  && left_topology.primitive_offsets = right_topology.primitive_offsets
  && Bytes.equal left_topology.primitive_kinds right_topology.primitive_kinds
  && List.equal (fun left right ->
       Attribute.owner left = Attribute.owner right
       && String.equal (Attribute.name left) (Attribute.name right)
       && equal_storage left right)
       (Geometry.attributes left) (Geometry.attributes right)
  && List.equal equal_group (Geometry.groups left) (Geometry.groups right)
  && List.equal equal_edge_group
       (Geometry.edge_groups left) (Geometry.edge_groups right)

let add_attribute owner name storage geometry =
  let attribute = Attribute.create_owned ~owner ~name storage |> get_ok in
  Geometry.with_attribute attribute geometry |> get_ok

let graph_fixture () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.; 2.; 3.; 2.; 2.; 10.; 11.; 10.5|]
      ~y:[|0.; 0.; 0.; 0.; 1.; -1.; 0.; 0.; 1.|]
      ~z:(Array.make 9 0.) in
  let vertex_points = [|
    0;1;2;3;
    2;4;
    2;5;
    0;1;
    5;5;
    6;7;8
  |] in
  let topology = Topology.create_owned ~point_count:9 ~vertex_points
      ~primitive_offsets:[|0;4;6;8;10;12;15|]
      ~primitive_kinds:[|Topology.Open_polyline; Topology.Open_polyline;
        Topology.Open_polyline; Topology.Open_polyline;
        Topology.Open_polyline; Topology.Polygon|] |> get_ok in
  let geometry = Geometry.create ~positions ~topology () |> get_ok in
  let geometry = geometry
      |> add_attribute Attribute.Point "point_float"
           (Attribute.Float (Array.init 9 float_of_int))
      |> add_attribute Attribute.Point "point_vector"
           (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
             ~x:(Array.init 9 float_of_int) ~y:(Array.make 9 2.)
             ~z:(Array.make 9 3.)))
      |> add_attribute Attribute.Point "point_quaternion"
           (Attribute.Float4 (Packed.Float4.of_owned
             ~x:(Array.init 9 float_of_int) ~y:(Array.make 9 0.)
             ~z:(Array.make 9 0.) ~w:(Array.make 9 1.) |> get_ok))
      |> add_attribute Attribute.Point "point_array"
           (Attribute.Int_array (Packed.Int_array.create_owned
             ~offsets:(Array.init 10 Fun.id) ~values:(Array.init 9 Fun.id)
             |> get_ok))
      |> add_attribute Attribute.Vertex "vertex_id"
           (Attribute.Int (Array.init 15 Fun.id))
      |> add_attribute Attribute.Vertex "vertex_weight"
           (Attribute.Float (Array.init 15 float_of_int))
      |> add_attribute Attribute.Vertex "vertex_name"
           (Attribute.Text (Array.init 15 (Printf.sprintf "v%d")))
      |> add_attribute Attribute.Vertex "vertex_uv"
           (Attribute.Float2 (Packed.Float2.of_owned
             ~x:(Array.init 15 float_of_int) ~y:(Array.make 15 0.) |> get_ok))
      |> add_attribute Attribute.Vertex "vertex_vector"
           (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
             ~x:(Array.init 15 float_of_int) ~y:(Array.make 15 1.)
             ~z:(Array.make 15 2.)))
      |> add_attribute Attribute.Vertex "vertex_quaternion"
           (Attribute.Float4 (Packed.Float4.of_owned
             ~x:(Array.init 15 float_of_int) ~y:(Array.make 15 0.)
             ~z:(Array.make 15 0.) ~w:(Array.make 15 1.) |> get_ok))
      |> add_attribute Attribute.Vertex "vertex_int_array"
           (Attribute.Int_array (Packed.Int_array.create_owned
             ~offsets:(Array.init 16 Fun.id) ~values:(Array.init 15 Fun.id)
             |> get_ok))
      |> add_attribute Attribute.Vertex "vertex_array"
           (Attribute.Float_array (Packed.Float_array.create_owned
             ~offsets:(Array.init 16 Fun.id)
             ~values:(Array.init 15 float_of_int) |> get_ok))
      |> add_attribute Attribute.Primitive "primitive_id"
           (Attribute.Int [|10;20;30;40;50;60|])
      |> add_attribute Attribute.Primitive "primitive_weight"
           (Attribute.Float [|1.;2.;3.;4.;5.;6.|])
      |> add_attribute Attribute.Primitive "primitive_name"
           (Attribute.Text [|"trunk";"up";"down";"duplicate";"self";"loop"|])
      |> add_attribute Attribute.Primitive "primitive_uv"
           (Attribute.Float2 (Packed.Float2.of_owned
             ~x:[|1.;2.;3.;4.;5.;6.|] ~y:(Array.make 6 0.) |> get_ok))
      |> add_attribute Attribute.Primitive "primitive_vector"
           (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
             ~x:[|1.;2.;3.;4.;5.;6.|] ~y:(Array.make 6 1.)
             ~z:(Array.make 6 2.)))
      |> add_attribute Attribute.Primitive "primitive_quaternion"
           (Attribute.Float4 (Packed.Float4.of_owned
             ~x:[|1.;2.;3.;4.;5.;6.|] ~y:(Array.make 6 0.)
             ~z:(Array.make 6 0.) ~w:(Array.make 6 1.) |> get_ok))
      |> add_attribute Attribute.Primitive "primitive_int_array"
           (Attribute.Int_array (Packed.Int_array.create_owned
             ~offsets:(Array.init 7 Fun.id) ~values:(Array.init 6 Fun.id)
             |> get_ok))
      |> add_attribute Attribute.Primitive "primitive_float_array"
           (Attribute.Float_array (Packed.Float_array.create_owned
             ~offsets:(Array.init 7 Fun.id)
             ~values:(Array.init 6 float_of_int) |> get_ok))
      |> add_attribute Attribute.Detail "tag" (Attribute.Text [|"fixture"|]) in
  let points = Group.init ~owner:Group.Point ~name:"even_points" 9
      (fun point -> point land 1 = 0)
  and vertices = Group.init ~owner:Group.Vertex ~name:"even_vertices" 15
      (fun vertex -> vertex land 1 = 0)
  and duplicate = Group.init ~owner:Group.Primitive ~name:"duplicate_source" 6
      (fun primitive -> primitive = 3) in
  let geometry = geometry |> Geometry.with_group points |> get_ok
      |> Geometry.with_group vertices |> get_ok
      |> Geometry.with_group duplicate |> get_ok in
  let index = Topology_index.create topology in
  let trunk = Edge_group.init ~topology ~index ~name:"trunk" (fun edge ->
      let a, b = Topology_index.edge_points index edge in
      (a = 0 && b = 1) || (a = 1 && b = 2)) in
  Geometry.with_edge_group trunk geometry |> get_ok

let attribute owner name geometry =
  Geometry.find_attribute ~owner name geometry |> Option.get

let test_topology_and_payload () =
  let source = graph_fixture () in
  let output = Ops.poly_path source |> get_pdk in
  check (Geometry.point_count output = 9
      && Geometry.vertex_count output = 13
      && Geometry.primitive_count output = 5)
    "PolyPath output cardinality";
  let topology = Topology.Private.view (Geometry.topology output) in
  check (topology.vertex_points =
      [|0;1;2; 2;3; 2;4; 2;5; 6;7;8;6|])
    "PolyPath maximal path ordering";
  check (topology.primitive_offsets = [|0;3;5;7;9;13|])
    "PolyPath primitive offsets";
  check (Array.for_all (( = ) Topology.Open_polyline)
      (Array.init 5 (Topology.primitive_kind (Geometry.topology output))))
    "PolyPath default loop kind";
  let vertex_id = attribute Attribute.Vertex "vertex_id" output in
  (match Attribute.Private.storage vertex_id with
   | Attribute.Int values ->
       check (values = [|0;1;2; 2;3; 4;5; 6;7; 12;13;14;12|])
         "PolyPath vertex ancestry"
   | _ -> fail "PolyPath vertex attribute kind changed");
  let primitive_id = attribute Attribute.Primitive "primitive_id" output in
  (match Attribute.Private.storage primitive_id with
   | Attribute.Int values ->
       check (values = [|10;10;20;30;60|])
         "PolyPath primitive ancestry"
   | _ -> fail "PolyPath primitive attribute kind changed");
  List.iter (fun (owner, name, expected) ->
    check (Attribute.length (attribute owner name output) = expected)
      ("PolyPath payload length for " ^ name))
    [Attribute.Point, "point_float", 9;
     Attribute.Point, "point_vector", 9;
     Attribute.Point, "point_quaternion", 9;
     Attribute.Point, "point_array", 9;
     Attribute.Vertex, "vertex_weight", 13;
     Attribute.Vertex, "vertex_name", 13;
     Attribute.Vertex, "vertex_uv", 13;
     Attribute.Vertex, "vertex_vector", 13;
     Attribute.Vertex, "vertex_quaternion", 13;
     Attribute.Vertex, "vertex_int_array", 13;
     Attribute.Vertex, "vertex_array", 13;
     Attribute.Primitive, "primitive_weight", 5;
     Attribute.Primitive, "primitive_name", 5;
     Attribute.Primitive, "primitive_uv", 5;
     Attribute.Primitive, "primitive_vector", 5;
     Attribute.Primitive, "primitive_quaternion", 5;
     Attribute.Primitive, "primitive_int_array", 5;
     Attribute.Primitive, "primitive_float_array", 5;
     Attribute.Detail, "tag", 1];
  let duplicate = Geometry.find_group ~owner:Group.Primitive
      "duplicate_source" output |> Option.get in
  check (Group.cardinality duplicate = 1 && Group.mem 0 duplicate)
    "PolyPath duplicate-edge primitive-group union ancestry";
  let point_group = Geometry.find_group ~owner:Group.Point "even_points" output
      |> Option.get in
  check (Group.cardinality point_group = 5)
    "PolyPath point group identity";
  let edge_group = Geometry.find_edge_group "trunk" output |> Option.get in
  check (Edge_group.length edge_group = 8
      && Edge_group.cardinality edge_group = 2
      && Edge_group.mem 0 edge_group && Edge_group.mem 1 edge_group)
    "PolyPath native edge-group ancestry";
  let closed = Ops.poly_path ~make_isolated_loops_closed:true source |> get_pdk in
  let closed_topology = Topology.Private.view (Geometry.topology closed) in
  check (Geometry.vertex_count closed = 12
      && closed_topology.vertex_points = [|0;1;2; 2;3; 2;4; 2;5; 6;7;8|]
      && Topology.primitive_kind (Geometry.topology closed) 4 = Topology.Polygon)
    "PolyPath isolated-loop closing"

let endpoint_fixture () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.; 1.04; 2.; 5.; 6.|]
      ~y:[|0.; 0.; 0.; 0.; 0.02; 1.|] ~z:(Array.make 6 0.) in
  let topology = Topology.create_owned ~point_count:6
      ~vertex_points:[|0;1; 2;3; 4;5|]
      ~primitive_offsets:[|0;2;4;6|]
      ~primitive_kinds:(Array.make 3 Topology.Open_polyline) |> get_ok in
  Geometry.create ~positions ~topology () |> get_ok

let test_endpoint_connection () =
  let source = endpoint_fixture () in
  let separate = Ops.poly_path source |> get_pdk in
  check (Geometry.primitive_count separate = 3)
    "PolyPath connected endpoints without opt-in";
  let connected = Ops.poly_path ~connect_end_points:true
      ~maximum_distance:0.05 ~connect_only_to_other_end_points:true source
      |> get_pdk in
  let topology = Topology.Private.view (Geometry.topology connected) in
  check (Geometry.point_count connected = 6
      && Geometry.primitive_count connected = 2
      && topology.vertex_points = [|0;1;3; 4;5|])
    (Printf.sprintf "PolyPath endpoint-pair rewiring: primitives=%d points=[%s]"
      (Geometry.primitive_count connected)
      (Array.to_list topology.vertex_points |> List.map string_of_int
       |> String.concat ";"));
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;2.;1.;1.02;1.02|]
      ~y:[|0.;0.;0.;1.;0.01;2.|] ~z:(Array.make 6 0.) in
  let topology = Topology.create_owned ~point_count:6
      ~vertex_points:[|0;1;2; 1;3; 4;5|]
      ~primitive_offsets:[|0;3;5;7|]
      ~primitive_kinds:(Array.make 3 Topology.Open_polyline) |> get_ok in
  let branch = Geometry.create ~positions ~topology () |> get_ok in
  let unrestricted = Ops.poly_path ~connect_end_points:true
      ~maximum_distance:0.05 branch |> get_pdk in
  let restricted = Ops.poly_path ~connect_end_points:true
      ~maximum_distance:0.05 ~connect_only_to_other_end_points:true branch
      |> get_pdk in
  let unrestricted_topology = Topology.Private.view
      (Geometry.topology unrestricted)
  and restricted_topology = Topology.Private.view
      (Geometry.topology restricted) in
  check (Geometry.primitive_count unrestricted = 4
      && Array.mem 1 unrestricted_topology.vertex_points
      && not (Array.mem 4 unrestricted_topology.vertex_points))
    "PolyPath endpoint-to-branch connection";
  check (Geometry.primitive_count restricted = 4
      && Array.mem 4 restricted_topology.vertex_points)
    "PolyPath endpoint-only restriction";
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;0.09;0.18; 5.;6.;7.;8.|]
      ~y:(Array.make 7 0.) ~z:(Array.make 7 0.) in
  let topology = Topology.create_owned ~point_count:7
      ~vertex_points:[|0;3; 4;1;5; 2;6|]
      ~primitive_offsets:[|0;2;5;7|]
      ~primitive_kinds:(Array.make 3 Topology.Open_polyline) |> get_ok in
  let chain = Geometry.create ~positions ~topology () |> get_ok in
  let chain = Ops.poly_path ~connect_end_points:true ~maximum_distance:0.1
      chain |> get_pdk in
  let chain_topology = Topology.Private.view (Geometry.topology chain) in
  check (not (Array.mem 1 chain_topology.vertex_points)
      && not (Array.mem 2 chain_topology.vertex_points))
    "PolyPath endpoint connection was not transitive through a rewired point";
  let huge_edge left right =
    let positions = Packed.Float3.Private.of_owned_exn
        ~x:[|left;right|] ~y:[|0.;0.|] ~z:[|0.;0.|] in
    let topology = Topology.create_owned ~point_count:2
        ~vertex_points:[|0;1|] ~primitive_offsets:[|0;2|]
        ~primitive_kinds:[|Topology.Open_polyline|] |> get_ok in
    Geometry.create ~positions ~topology () |> get_ok in
  let outside = huge_edge (-1e308) 1e308
      |> Ops.poly_path ~connect_end_points:true ~maximum_distance:1e308
      |> get_pdk
  and inclusive = huge_edge (-5e307) 5e307
      |> Ops.poly_path ~connect_end_points:true ~maximum_distance:1e308
      |> get_pdk in
  check (Geometry.primitive_count outside = 1)
    "PolyPath overflowed an extreme endpoint distance";
  check (Geometry.primitive_count inclusive = 0)
    "PolyPath endpoint maximum distance was not inclusive"

let test_empty_and_failures () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.|] ~y:[|0.; 0.|] ~z:[|0.; 0.|] in
  let topology = Topology.create_owned ~point_count:2 ~vertex_points:[||]
      ~primitive_offsets:[|0|] ~primitive_kinds:[||] |> get_ok in
  let empty = Geometry.create ~positions ~topology () |> get_ok
      |> add_attribute Attribute.Point "id" (Attribute.Int [|0;1|]) in
  let output = Ops.poly_path empty |> get_pdk in
  check (Geometry.point_count output = 2 && Geometry.vertex_count output = 0
      && Geometry.primitive_count output = 0)
    "PolyPath empty graph";
  let self_topology = Topology.create_owned ~point_count:1
      ~vertex_points:[|0;0|] ~primitive_offsets:[|0;2|]
      ~primitive_kinds:[|Topology.Open_polyline|] |> get_ok in
  let self_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.|] ~y:[|0.|] ~z:[|0.|] in
  let self = Geometry.create ~positions:self_positions ~topology:self_topology ()
      |> get_ok
      |> add_attribute Attribute.Vertex "corner" (Attribute.Int [|4;5|])
      |> add_attribute Attribute.Primitive "face" (Attribute.Text [|"self"|]) in
  let self_group = Group.init ~owner:Group.Primitive ~name:"self" 1
      (fun _ -> true) in
  let self = Geometry.with_group self_group self |> get_ok in
  let self_index = Topology_index.create self_topology in
  let self_edges = Edge_group.init ~topology:self_topology ~index:self_index
      ~name:"self_edge" (fun _ -> true) in
  let self = Geometry.with_edge_group self_edges self |> get_ok in
  let self_output = Ops.poly_path self |> get_pdk in
  check (Geometry.point_count self_output = 1
      && Geometry.vertex_count self_output = 0
      && Geometry.primitive_count self_output = 0
      && Attribute.length (attribute Attribute.Vertex "corner" self_output) = 0
      && Attribute.length (attribute Attribute.Primitive "face" self_output) = 0
      && Group.cardinality (Geometry.find_group ~owner:Group.Primitive
           "self" self_output |> Option.get) = 0
      && Edge_group.length (Geometry.find_edge_group "self_edge" self_output
           |> Option.get) = 0)
    "PolyPath self-edge-only payload cleanup";
  (match Ops.poly_path ~maximum_distance:Float.nan (graph_fixture ()) with
   | Error error -> check (Error.code error = "invalid_geometry")
       "PolyPath non-finite distance error code"
   | Ok _ -> fail "PolyPath accepted a non-finite distance");
  let nonfinite = endpoint_fixture () in
  let source = Packed.Float3.Private.view (Geometry.positions nonfinite) in
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:(Array.mapi (fun point value -> if point = 5 then Float.nan else value)
        source.x) ~y:(Array.copy source.y) ~z:(Array.copy source.z) in
  let nonfinite = Geometry.with_positions positions nonfinite |> get_ok in
  check (Result.is_ok (Ops.poly_path nonfinite))
    "PolyPath inspected positions when endpoint connection was disabled";
  (match Ops.poly_path ~connect_end_points:true nonfinite with
   | Error error -> check (Error.code error = "invalid_geometry")
       "PolyPath non-finite endpoint error code"
   | Ok _ -> fail "PolyPath connected non-finite endpoints");
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.poly_path ~cancel:cancelled (graph_fixture ()) with
   | Error error -> check (Error.code error = "cancelled")
       "PolyPath cancellation error code"
   | Ok _ -> fail "cancelled PolyPath published geometry");
  match Ops.poly_path ~grain:0 (graph_fixture ()) with
  | Error error -> check (Error.code error = "invalid_geometry")
      "PolyPath grain error code"
  | Ok _ -> fail "PolyPath accepted zero grain"

let scale_fixture columns rows =
  let point_count = (columns + 1) * (rows + 1) in
  let point x y = y * (columns + 1) + x in
  let primitive_count = rows * (columns + 1) + columns * (rows + 1) in
  let vertex_points = Array.make (primitive_count * 2) 0
  and primitive_offsets = Array.init (primitive_count + 1) (fun p -> p * 2) in
  let primitive = ref 0 in
  for x = 0 to columns do
    for y = 0 to rows - 1 do
      vertex_points.(!primitive * 2) <- point x y;
      vertex_points.(!primitive * 2 + 1) <- point x (y + 1);
      incr primitive
    done
  done;
  for y = 0 to rows do
    for x = 0 to columns - 1 do
      vertex_points.(!primitive * 2) <- point x y;
      vertex_points.(!primitive * 2 + 1) <- point (x + 1) y;
      incr primitive
    done
  done;
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:(Array.init point_count (fun p -> float_of_int (p mod (columns + 1))))
      ~y:(Array.init point_count (fun p -> float_of_int (p / (columns + 1))))
      ~z:(Array.make point_count 0.) in
  let topology = Topology.create_owned ~point_count ~vertex_points
      ~primitive_offsets
      ~primitive_kinds:(Array.make primitive_count Topology.Open_polyline)
      |> get_ok in
  let geometry = Geometry.create ~positions ~topology () |> get_ok
      |> add_attribute Attribute.Point "id"
           (Attribute.Int (Array.init point_count Fun.id))
      |> add_attribute Attribute.Vertex "corner"
           (Attribute.Float (Array.init (primitive_count * 2) float_of_int))
      |> add_attribute Attribute.Primitive "source"
           (Attribute.Int (Array.init primitive_count Fun.id)) in
  let group = Group.init ~owner:Group.Primitive ~name:"alternating"
      primitive_count (fun p -> p land 1 = 0) in
  let geometry = Geometry.with_group group geometry |> get_ok in
  let index = Topology_index.create topology in
  let edges = Edge_group.init ~topology ~index ~name:"alternating_edges"
      (fun edge -> edge land 1 = 0) in
  Geometry.with_edge_group edges geometry |> get_ok

let test_parallel_exact () =
  let source = scale_fixture 400 300 in
  let run domains = Parallel.run ~domains (fun () ->
      Ops.poly_path ~grain:257 source |> get_pdk) in
  let one = run 1 and four = run 4 in
  check (equal_geometry one four)
    "PolyPath differs between one and four domains";
  let expected_edges = (400 * 301) + (300 * 401) in
  check (Topology_index.edge_count
      (Topology_index.create (Geometry.topology one)) = expected_edges)
    "PolyPath scale edge cardinality"

let () =
  test_topology_and_payload ();
  test_endpoint_connection ();
  test_empty_and_failures ();
  test_parallel_exact ();
  print_endline "poly path tests passed"
