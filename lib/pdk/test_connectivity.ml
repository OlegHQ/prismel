open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function
  | Ok value -> value
  | Error error -> fail (Error.to_string error)

let two_quads () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.; 2.; 0.; 1.; 2.|]
      ~y:[|0.; 0.; 0.; 1.; 1.; 1.|]
      ~z:(Array.make 6 0.) in
  let topology = Topology.Builder.create ~point_count:6 () in
  Topology.Builder.add_polygon topology [|0; 1; 4; 3|];
  Topology.Builder.add_polygon topology [|1; 2; 5; 4|];
  Geometry.create ~positions ~topology:(Topology.Builder.freeze topology) ()
  |> function Ok geometry -> geometry | Error message -> fail message

let with_group owner name predicate geometry =
  let length = match owner with
    | Group.Point -> Geometry.point_count geometry
    | Group.Vertex -> Geometry.vertex_count geometry
    | Group.Primitive -> Geometry.primitive_count geometry in
  Geometry.with_group (Group.init ~grain:1 ~owner ~name length predicate) geometry
  |> function Ok geometry -> geometry | Error message -> fail message

let shared_edge geometry =
  let topology = Geometry.topology geometry in
  let index = Topology_index.create topology in
  match Topology_index.find_edge index ~a:1 ~b:4 with
  | None -> fail "fixture has no shared edge"
  | Some shared ->
      Edge_group.init ~grain:1 ~topology ~index ~name:"seam"
        (fun edge -> edge = shared)

let with_uv name values geometry =
  let packed = Packed.Float2.of_owned
      ~x:(Array.map fst values) ~y:(Array.map snd values)
    |> function Ok packed -> packed | Error message -> fail message in
  let attribute = Attribute.create_owned ~name ~owner:Attribute.Vertex
      (Attribute.Float2 packed)
    |> function Ok attribute -> attribute | Error message -> fail message in
  Geometry.with_attribute attribute geometry
  |> function Ok geometry -> geometry | Error message -> fail message

let int_attribute owner name geometry =
  Geometry.find_attribute ~owner name geometry |> Option.get
  |> Attribute.get (Attribute.key ~owner ~name Attribute.int) |> Option.get

let text_attribute owner name geometry =
  Geometry.find_attribute ~owner name geometry |> Option.get
  |> Attribute.get (Attribute.key ~owner ~name Attribute.text) |> Option.get

let expect_error code = function
  | Error error -> check (Error.code error = code)
      (Printf.sprintf "expected error %S, got %S" code (Error.code error))
  | Ok _ -> fail ("expected error " ^ code)

let test_point_and_primitive_modes () =
  let geometry = two_quads () in
  let classes, count = Analysis.classify_connectivity
      Analysis.Connectivity_primitives geometry |> get_ok in
  check (classes = [|0; 0|] && count = 1)
    "shared-point primitive connectivity";
  let classes, count = Analysis.classify_connectivity
      Analysis.Connectivity_points geometry |> get_ok in
  check (classes = [|0; 0; 0; 0; 0; 0|] && count = 1)
    "edge-connected point connectivity";
  let masked = with_group Group.Point "without_bridge"
      (fun point -> point <> 1 && point <> 4) geometry in
  let points = Geometry.find_group ~owner:Group.Point "without_bridge" masked
      |> Option.get in
  let classes, count = Analysis.classify_connectivity ~points
      Analysis.Connectivity_points masked |> get_ok in
  check (classes = [|0; -1; 1; 0; -1; 1|] && count = 2)
    "excluded bridge points split the point graph";
  let masked = with_group Group.Primitive "right" (fun primitive -> primitive = 1)
      geometry in
  let primitives = Geometry.find_group ~owner:Group.Primitive "right" masked
      |> Option.get in
  let classes, count = Analysis.classify_connectivity ~primitives
      Analysis.Connectivity_primitives masked |> get_ok in
  check (classes = [|-1; 0|] && count = 1)
    "excluded primitives retain the minus-one sentinel"

let test_seams_and_uv_islands () =
  let geometry = two_quads () in
  let seam = shared_edge geometry in
  let classes, count = Analysis.classify_connectivity ~seams:seam
      Analysis.Connectivity_primitives geometry |> get_ok in
  check (classes = [|0; 1|] && count = 2)
    "native shared-edge seam did not split primitive islands";
  let continuous = with_uv "uv" [|
      0., 0.; 1., 0.; 1., 1.; 0., 1.;
      1., 0.; 2., 0.; 2., 1.; 1., 1.|] geometry in
  let classes, count = Analysis.classify_connectivity ~uv_attribute:"uv"
      Analysis.Connectivity_primitives continuous |> get_ok in
  check (classes = [|0; 0|] && count = 1)
    "equal endpoint UVs split a continuous island";
  let discontinuous = with_uv "uv" [|
      0., 0.; 1., 0.; 1., 1.; 0., 1.;
      3., 0.; 4., 0.; 4., 1.; 3., 1.|] geometry in
  let classes, count = Analysis.classify_connectivity ~uv_attribute:"uv"
      Analysis.Connectivity_primitives discontinuous |> get_ok in
  check (classes = [|0; 1|] && count = 2)
    "UV discontinuity did not split primitive islands"

let test_attribute_output () =
  let geometry = two_quads () |> with_group Group.Primitive "right"
      (fun primitive -> primitive = 1) in
  let primitives = Geometry.find_group ~owner:Group.Primitive "right" geometry
      |> Option.get in
  let integer = Analysis.with_connectivity ~primitives ~name:"piece"
      geometry |> get_ok in
  check (int_attribute Attribute.Primitive "piece" integer = [|-1; 0|])
    "integer class attribute";
  let text = Analysis.with_connectivity ~primitives ~name:"island"
      ~attribute:(Analysis.Connectivity_text "tile_") geometry |> get_ok in
  check (text_attribute Attribute.Primitive "island" text = [|""; "tile_0"|])
    "prefixed text class attribute and excluded sentinel";
  let points = Analysis.with_connectivity ~owner:Analysis.Connectivity_points
      ~name:"point_piece" geometry |> get_ok in
  check (int_attribute Attribute.Point "point_piece" points
      = [|0; 0; 0; 0; 0; 0|]) "point-owned class attribute"

let test_validation_and_cancellation () =
  let geometry = two_quads () in
  let point_group = Group.init ~owner:Group.Point ~name:"points" 6 (fun _ -> true)
  and wrong_length = Group.init ~owner:Group.Primitive ~name:"bad" 1 (fun _ -> true)
  and seam = shared_edge geometry in
  expect_error "invalid_connectivity"
    (Analysis.classify_connectivity ~points:point_group
       Analysis.Connectivity_primitives geometry);
  let point_classes, point_count = Analysis.classify_connectivity ~seams:seam
      Analysis.Connectivity_points geometry |> get_ok in
  check (Array.length point_classes = Geometry.point_count geometry
      && point_count = 1)
    "point seam classification did not preserve the connected remainder";
  expect_error "invalid_connectivity"
    (Analysis.classify_connectivity ~seams:seam ~uv_attribute:"uv"
       Analysis.Connectivity_primitives geometry);
  expect_error "invalid_connectivity"
    (Analysis.classify_connectivity ~primitives:wrong_length
       Analysis.Connectivity_primitives geometry);
  expect_error "invalid_connectivity"
    (Analysis.classify_connectivity ~uv_attribute:"missing"
       Analysis.Connectivity_primitives geometry);
  expect_error "invalid_parameter"
    (Analysis.classify_connectivity ~grain:0
       Analysis.Connectivity_primitives geometry);
  let unrelated = two_quads () in
  expect_error "invalid_connectivity"
    (Analysis.classify_connectivity ~seams:(shared_edge unrelated)
       Analysis.Connectivity_primitives geometry);
  let bad_uv = Attribute.create_owned ~name:"bad_uv" ~owner:Attribute.Vertex
      (Attribute.Int (Array.make 8 0))
    |> function Ok attribute -> attribute | Error message -> fail message in
  let bad_uv_geometry = Geometry.with_attribute bad_uv geometry
      |> function Ok value -> value | Error message -> fail message in
  expect_error "invalid_connectivity"
    (Analysis.classify_connectivity ~uv_attribute:"bad_uv"
       Analysis.Connectivity_primitives bad_uv_geometry);
  let cancel = Cancel.create () in
  Cancel.cancel cancel;
  expect_error "cancelled"
    (Analysis.classify_connectivity ~cancel
       Analysis.Connectivity_primitives geometry)

let test_parallel_exactness () =
  let geometry = Ops.grid ~columns:500 ~rows:300 ~size:10. () |> get_ok in
  let run domains = Parallel.run ~domains (fun () ->
    Analysis.with_connectivity ~grain:257
      ~owner:Analysis.Connectivity_points ~name:"island"
      ~attribute:(Analysis.Connectivity_text "component_") geometry |> get_ok)
  in
  let one = run 1 and four = run 4 in
  check (text_attribute Attribute.Point "island" one
      = text_attribute Attribute.Point "island" four)
    "Connectivity one/four-domain text output differs";
  check (Geometry.point_count one = 150_801)
    "Connectivity scale cardinality"

let () =
  test_point_and_primitive_modes ();
  test_seams_and_uv_islands ();
  test_attribute_output ();
  test_validation_and_cancellation ();
  test_parallel_exactness ();
  print_endline "connectivity tests passed"
