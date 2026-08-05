open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function Ok value -> value | Error message -> fail message
let get_pdk = function Ok value -> value | Error error -> fail (Error.to_string error)

let geometry_owned ~kinds positions vertex_points primitive_offsets =
  let positions = Array.of_list positions in
  let point_count = Array.length positions in
  let x = Array.map (fun (x, _, _) -> x) positions
  and y = Array.map (fun (_, y, _) -> y) positions
  and z = Array.map (fun (_, _, z) -> z) positions in
  let topology = Topology.create_owned ~point_count ~vertex_points
      ~primitive_offsets ~primitive_kinds:kinds |> get_ok in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> get_ok

let disjoint () = geometry_owned
    ~kinds:(Array.make 3 Topology.Open_polyline)
    [0.,0.,0.; 1.,0.,0.; 3.,0.,0.; 5.,0.,0.; 7.,0.,0.; 10.,0.,0.]
    [|0;1; 2;3; 4;5|] [|0;2;4;6|]

let positions geometry = Packed.Float3.Private.view (Geometry.positions geometry)

let edge_group_of_pairs topology name pairs =
  let index = Topology_index.create topology in
  let selected = Array.map (fun (a, b) ->
      let edge = Topology_index.find_edge_index index ~a ~b in
      if edge < 0 then fail "test edge is absent";
      edge) pairs in
  Edge_group.init ~grain:1 ~topology ~index ~name (fun edge ->
    Array.mem edge selected)

let expect_code code = function
  | Error error when Error.code error = code -> ()
  | Error error -> fail (Printf.sprintf "expected %s, received %s: %s"
      code (Error.code error) (Error.to_string error))
  | Ok _ -> fail ("expected error " ^ code)

let close left right = abs_float (left -. right) <= 4e-6
let array_close left right = Array.length left = Array.length right
  && Array.for_all2 close left right

let equal_geometry left right =
  let left_positions = positions left and right_positions = positions right in
  left_positions.x = right_positions.x
  && left_positions.y = right_positions.y
  && left_positions.z = right_positions.z
  && Topology.point_count (Geometry.topology left)
     = Topology.point_count (Geometry.topology right)
  && List.length (Geometry.edge_groups left) = List.length (Geometry.edge_groups right)
  && List.for_all2 (fun left right ->
       Edge_group.name left = Edge_group.name right
       && Edge_group.length left = Edge_group.length right
       && let same = ref true in
          for edge = 0 to Edge_group.length left - 1 do
            if Edge_group.mem edge left <> Edge_group.mem edge right then
              same := false
          done;
          !same)
       (Geometry.edge_groups left) (Geometry.edge_groups right)

let many_disjoint edge_count =
  let point_count = edge_count * 2 in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. in
  for edge = 0 to edge_count - 1 do
    let point = edge * 2 and base = float_of_int edge *. 4.
    and length = 0.5 +. float_of_int (edge mod 17) *. 0.1 in
    x.(point) <- base; x.(point + 1) <- base +. length
  done;
  let positions = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
  let topology = Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (edge_count + 1) (fun edge -> edge * 2))
      ~primitive_kinds:(Array.make edge_count Topology.Open_polyline) |> get_ok in
  Geometry.create ~positions ~topology () |> get_ok

let many_chains count =
  let point_count = count * 3 in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. in
  for chain = 0 to count - 1 do
    let point = chain * 3 and base = float_of_int chain *. 5. in
    x.(point) <- base;
    x.(point + 1) <- base +. 0.5 +. float_of_int (chain mod 5) *. 0.1;
    x.(point + 2) <- base +. 2.5
  done;
  let positions = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
  let topology = Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (count + 1) (fun chain -> chain * 3))
      ~primitive_kinds:(Array.make count Topology.Open_polyline) |> get_ok in
  Geometry.create ~positions ~topology () |> get_ok

let all_edge_lengths geometry =
  let p = positions geometry and index = Topology_index.create
      (Geometry.topology geometry) in
  Array.init (Topology_index.edge_count index) (fun edge ->
    let a, b = Topology_index.edge_points index edge in
    let dx = p.x.(b) -. p.x.(a) and dy = p.y.(b) -. p.y.(a)
    and dz = p.z.(b) -. p.z.(a) in
    sqrt (dx *. dx +. dy *. dy +. dz *. dz))

let () =
  let source = disjoint () in
  let average = Ops.edge_equalize ~grain:1 ~output_group:"equalized" source
      |> get_pdk in
  check (array_close (positions average).x [|-.0.5;1.5;3.;5.;7.5;9.5|])
    "Edge Equalize average result";
  check ((positions average).y = Array.make 6 0.
      && (positions average).z = Array.make 6 0.)
    "Edge Equalize changed orthogonal planes";
  check ((positions average).y == (positions source).y
      && (positions average).z == (positions source).z)
    "Edge Equalize did not share unchanged coordinate planes";
  let output_group = Geometry.find_edge_group "equalized" average
      |> Option.get in
  check (Edge_group.cardinality output_group = 3)
    "Edge Equalize output group cardinality";
  let longest = Ops.edge_equalize ~method_:Ops.Equalize_longest source
      |> get_pdk in
  check (array_close (positions longest).x [|-1.;2.;2.5;5.5;7.;10.|])
    "Edge Equalize longest result";
  let shortest = Ops.edge_equalize ~method_:Ops.Equalize_shortest source
      |> get_pdk in
  check (array_close (positions shortest).x [|0.;1.;3.5;4.5;8.;9.|])
    "Edge Equalize shortest result";

  let subset = edge_group_of_pairs (Geometry.topology source) "outer"
      [|0,1;4,5|] in
  let subset_output = Ops.edge_equalize ~edges:subset source |> get_pdk in
  check (array_close (positions subset_output).x
      [|-0.5;1.5;3.;5.;7.5;9.5|])
    "Edge Equalize subset moved an unselected edge";

  let chain = Ops.polyline [|0.,0.,0.;1.,0.,0.;4.,0.,0.;6.,0.,0.|]
      |> get_pdk in
  let chain_output = Ops.edge_equalize ~grain:1 chain |> get_pdk in
  let p = positions chain_output in
  check (close (p.x.(1) -. p.x.(0)) 2.
      && close (p.x.(2) -. p.x.(1)) 2.
      && close (p.x.(3) -. p.x.(2)) 2.)
    (Printf.sprintf "Edge Equalize connected convergence: %.12g %.12g %.12g"
      (p.x.(1) -. p.x.(0)) (p.x.(2) -. p.x.(1))
      (p.x.(3) -. p.x.(2)));
  check (close (Array.fold_left ( +. ) 0. p.x) 11.)
    "Edge Equalize did not preserve the connected centroid";
  expect_code "invalid_edge_equalize"
    (Ops.edge_equalize ~iterations:1 ~tolerance:1e-12 chain);

  let cycle = Ops.polyline ~closed:true
      [|(-1.,-0.6,0.);(1.4,-0.8,0.);(0.8,1.2,0.);(-0.7,0.9,0.)|]
      |> get_pdk |> Ops.edge_equalize ~iterations:160 ~tolerance:1e-7
      |> get_pdk in
  let cycle_lengths = all_edge_lengths cycle in
  check (Array.for_all (fun length ->
      abs_float (length -. cycle_lengths.(0)) < 2e-6) cycle_lengths)
    "Edge Equalize cycle convergence";
  let branch = geometry_owned ~kinds:(Array.make 4 Topology.Open_polyline)
      [0.,0.,0.;1.,0.,0.;0.,2.,0.;-3.,0.,0.;0.,-4.,0.]
      [|0;1;0;2;0;3;0;4|] [|0;2;4;6;8|]
      |> Ops.edge_equalize ~iterations:160 ~tolerance:1e-7 |> get_pdk in
  let branch_lengths = all_edge_lengths branch in
  check (Array.for_all (fun length ->
      abs_float (length -. branch_lengths.(0)) < 2e-6) branch_lengths)
    "Edge Equalize branch convergence";

  let equal = geometry_owned ~kinds:(Array.make 2 Topology.Open_polyline)
      [0.,0.,0.;1.,0.,0.; 3.,0.,0.;4.,0.,0.]
      [|0;1;2;3|] [|0;2;4|] in
  check (Ops.edge_equalize equal |> get_pdk == equal)
    "already-equal edges were not an identity";
  let empty = edge_group_of_pairs (Geometry.topology source) "empty" [||] in
  check (Ops.edge_equalize ~edges:empty source |> get_pdk == source)
    "empty Edge Equalize was not an identity";
  let empty_output = Ops.edge_equalize ~edges:empty ~output_group:"none" source
      |> get_pdk in
  check (Geometry.find_edge_group "none" empty_output |> Option.get
      |> Edge_group.cardinality = 0)
    "empty Edge Equalize omitted its output group";

  let zero = geometry_owned ~kinds:(Array.make 2 Topology.Open_polyline)
      [0.,0.,0.;0.,0.,0.; 2.,0.,0.;4.,0.,0.]
      [|0;1;2;3|] [|0;2;4|] in
  let collapsed = Ops.edge_equalize ~method_:Ops.Equalize_shortest zero
      |> get_pdk |> positions in
  check (array_close collapsed.x [|0.;0.;3.;3.|])
    "Edge Equalize shortest zero target";
  expect_code "invalid_edge_equalize" (Ops.edge_equalize zero);

  let other = disjoint () in
  let foreign = edge_group_of_pairs (Geometry.topology other) "foreign"
      [|0,1|] in
  expect_code "invalid_edge_equalize" (Ops.edge_equalize ~edges:foreign source);
  expect_code "invalid_edge_equalize" (Ops.edge_equalize ~grain:0 source);
  expect_code "invalid_edge_equalize" (Ops.edge_equalize ~iterations:0 source);
  expect_code "invalid_edge_equalize" (Ops.edge_equalize ~tolerance:nan source);
  expect_code "invalid_edge_equalize" (Ops.edge_equalize ~tolerance:0. source);
  expect_code "invalid_edge_equalize"
    (Ops.edge_equalize ~output_group:" " source);
  let non_finite = geometry_owned ~kinds:[|Topology.Open_polyline|]
      [0.,0.,0.;nan,0.,0.] [|0;1|] [|0;2|] in
  expect_code "invalid_edge_equalize" (Ops.edge_equalize non_finite);
  let unrepresentable = geometry_owned ~kinds:[|Topology.Open_polyline|]
      [max_float,0.,0.;-.max_float,0.,0.] [|0;1|] [|0;2|] in
  expect_code "invalid_edge_equalize" (Ops.edge_equalize unrepresentable);
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  expect_code "cancelled" (Ops.edge_equalize ~cancel:cancelled source);

  let decorated =
    let normal = Attribute.create_owned ~owner:Attribute.Point ~name:"N"
        (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
          ~x:(Array.make 6 0.) ~y:(Array.make 6 0.) ~z:(Array.make 6 1.)))
        |> get_ok in
    Geometry.with_attribute normal source |> get_ok in
  let decorated_output = Ops.edge_equalize decorated |> get_pdk in
  check (Geometry.topology decorated_output == Geometry.topology decorated
      && Geometry.find_attribute ~owner:Attribute.Point "N" decorated_output = None)
    "Edge Equalize payload sharing or normal invalidation";

  let large = many_disjoint 50_000 in
  let run domains = Parallel.run ~domains (fun () ->
      Ops.edge_equalize ~grain:127 ~output_group:"eq" large |> get_pdk) in
  let one = run 1 and four = run 4 in
  check (equal_geometry one four)
    "Edge Equalize differs across domain counts";
  check (Geometry.point_count one = 100_000
      && Geometry.vertex_count one = 100_000
      && Geometry.primitive_count one = 50_000)
    "Edge Equalize scale cardinality";
  let connected = many_chains 5_000 in
  let run_connected domains = Parallel.run ~domains (fun () ->
      Ops.edge_equalize ~grain:127 ~iterations:96 connected |> get_pdk) in
  let connected_one = run_connected 1 and connected_four = run_connected 4 in
  check (equal_geometry connected_one connected_four)
    "connected Edge Equalize differs across domain counts";
  check (Geometry.point_count connected_one = 15_000
      && Geometry.primitive_count connected_one = 5_000)
    "connected Edge Equalize scale cardinality";
  print_endline "edge equalize tests passed"
