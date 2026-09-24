open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function Ok value -> value | Error message -> fail message
let get_pdk = function Ok value -> value | Error error -> fail (Error.to_string error)
let positions geometry = Packed.Float3.Private.view (Geometry.positions geometry)

let disjoint lengths =
  let edge_count = Array.length lengths and point_count = Array.length lengths * 2 in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. in
  Array.iteri (fun edge length ->
    let point = edge * 2 and base = float_of_int edge *. 5. in
    x.(point) <- base; x.(point + 1) <- base +. length) lengths;
  let topology = Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (edge_count + 1) (fun edge -> edge * 2))
      ~primitive_kinds:(Array.make edge_count Topology.Open_polyline) |> get_ok in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> get_ok

let edge_lengths geometry =
  let p = positions geometry and index = Topology_index.create
      (Geometry.topology geometry) in
  Array.init (Topology_index.edge_count index) (fun edge ->
    let a, b = Topology_index.edge_points index edge in
    let dx = p.x.(b) -. p.x.(a) and dy = p.y.(b) -. p.y.(a)
    and dz = p.z.(b) -. p.z.(a) in
    sqrt (dx *. dx +. dy *. dy +. dz *. dz))

let close left right = abs_float (left -. right) < 1e-5
let array_close left right = Array.for_all2 close left right

let group owner name length predicate = Group.init ~grain:1 ~owner ~name length predicate

let expect_code code = function
  | Error error when Error.code error = code -> ()
  | Error error -> fail (Printf.sprintf "expected %s, received %s: %s"
      code (Error.code error) (Error.to_string error))
  | Ok _ -> fail ("expected error " ^ code)

let equal_geometry left right =
  let left = positions left and right = positions right in
  left.x = right.x && left.y = right.y && left.z = right.z

let () =
  let source = disjoint [|1.;2.;3.|]
  and reference = disjoint [|2.;1.;4.|] in
  let output = Ops.edge_relax ~reference source |> get_pdk in
  check (array_close (edge_lengths output) [|2.;1.;4.|])
    "Edge Relax individual targets";
  check (Geometry.topology output == Geometry.topology source)
    "Edge Relax did not share topology";
  let normal = Attribute.create_owned ~owner:Attribute.Point ~name:"N"
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:(Array.make 6 0.) ~y:(Array.make 6 0.) ~z:(Array.make 6 1.)))
      |> get_ok in
  let decorated = Geometry.with_attribute normal source |> get_ok in
  let decorated_output = Ops.edge_relax ~reference decorated |> get_pdk in
  check (Geometry.find_attribute ~owner:Attribute.Point "N" decorated_output = None
      && Geometry.topology decorated_output == Geometry.topology decorated)
    "Edge Relax retained stale normals or rebuilt topology";

  let distribution_reference = disjoint [|2.;4.;6.|] in
  let distributed = Ops.edge_relax ~reference:distribution_reference
      ~target_mode:Ops.Scale_independent_distribution source |> get_pdk in
  check (array_close (edge_lengths distributed) [|1.;2.;3.|])
    "Edge Relax scale-independent distribution";

  let shorten_source = disjoint [|1.;3.|]
  and shorten_reference = disjoint [|2.;2.|] in
  let shortened = Ops.edge_relax ~reference:shorten_reference
      ~only_shorten:true shorten_source |> get_pdk in
  check (array_close (edge_lengths shortened) [|1.;2.|])
    "Edge Relax shorten-only policy";

  let point_selection = group Group.Point "last" 6 (fun point -> point = 5) in
  let selected = Ops.edge_relax ~reference ~selection:(Ops.Relax_points point_selection)
      ~iterations:64 source |> get_pdk in
  check (array_close (edge_lengths selected) [|1.;2.;4.|])
    "Edge Relax point restriction";
  let primitive_selection = group Group.Primitive "middle" 3
      (fun primitive -> primitive = 1) in
  let selected = Ops.edge_relax ~reference
      ~selection:(Ops.Relax_primitives primitive_selection) source |> get_pdk in
  check (array_close (edge_lengths selected) [|1.;1.;3.|])
    "Edge Relax primitive restriction";
  let pins = group Group.Point "pins" 6 (fun point -> point land 1 = 0) in
  let pinned = Ops.edge_relax ~reference ~pin_points:pins ~iterations:64 source
      |> get_pdk in
  check (array_close (edge_lengths pinned) [|2.;1.;4.|]
      && (positions pinned).x.(0) = (positions source).x.(0)
      && (positions pinned).x.(2) = (positions source).x.(2)
      && (positions pinned).x.(4) = (positions source).x.(4))
    "Edge Relax pin group";

  check (Ops.edge_relax ~reference:source source |> get_pdk == source)
    "Edge Relax matching reference was not an identity";
  let wrong_topology = Ops.polyline [|0.,0.,0.;1.,0.,0.;2.,0.,0.|] |> get_pdk in
  expect_code "invalid_edge_relax" (Ops.edge_relax ~reference:wrong_topology source);
  expect_code "invalid_edge_relax" (Ops.edge_relax ~reference ~grain:0 source);
  expect_code "invalid_edge_relax" (Ops.edge_relax ~reference ~iterations:0 source);
  expect_code "invalid_edge_relax" (Ops.edge_relax ~reference ~step_size:1.1 source);
  expect_code "invalid_edge_relax" (Ops.edge_relax ~reference ~tolerance:nan source);
  let wrong_owner = group Group.Primitive "wrong" 3 (Fun.const true) in
  expect_code "invalid_edge_relax"
    (Ops.edge_relax ~reference ~selection:(Ops.Relax_points wrong_owner) source);
  let zero = disjoint [|0.;1.|] and positive = disjoint [|1.;1.|] in
  expect_code "invalid_edge_relax" (Ops.edge_relax ~reference:positive zero);
  let non_finite_reference =
    let p = positions reference in
    Geometry.with_positions (Packed.Float3.Private.of_shared_exn
      ~x:[|0.;nan;3.;4.;7.;11.|] ~y:p.y ~z:p.z) reference |> get_ok in
  expect_code "invalid_edge_relax"
    (Ops.edge_relax ~reference:non_finite_reference source);
  let zero_reference = disjoint [|0.;0.;0.|] in
  expect_code "invalid_edge_relax" (Ops.edge_relax
    ~reference:zero_reference ~target_mode:Ops.Scale_independent_distribution
    source);
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  expect_code "cancelled" (Ops.edge_relax ~cancel:cancelled ~reference source);

  let large_source = disjoint (Array.init 50_000 (fun edge ->
      0.5 +. float_of_int (edge mod 17) *. 0.1))
  and large_reference = disjoint (Array.init 50_000 (fun edge ->
      0.8 +. float_of_int (edge mod 11) *. 0.1)) in
  let run domains = Parallel.run ~domains (fun () ->
      Ops.edge_relax ~grain:127 ~reference:large_reference large_source
      |> get_pdk) in
  let one = run 1 and four = run 4 in
  check (equal_geometry one four)
    "Edge Relax differs across domain counts";
  check (Geometry.point_count one = 100_000
      && Geometry.primitive_count one = 50_000)
    "Edge Relax scale cardinality";
  let connected_source = Ops.polyline
      [|0.,0.,0.;1.,0.4,0.;3.,-0.2,0.;6.,0.5,0.|] |> get_pdk
  and connected_reference = Ops.polyline
      [|0.,0.,0.;2.,0.,0.;3.,0.,0.;7.,0.,0.|] |> get_pdk in
  let run_connected domains = Parallel.run ~domains (fun () ->
      Ops.edge_relax ~grain:1 ~iterations:96 ~reference:connected_reference
        connected_source |> get_pdk) in
  check (equal_geometry (run_connected 1) (run_connected 4))
    "connected Edge Relax differs across domain counts";
  print_endline "edge relax tests passed"
