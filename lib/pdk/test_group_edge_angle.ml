open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function
  | Ok value -> value
  | Error error -> fail (Error.to_string error)

let geometry positions curves =
  let packed = Packed.Float3.Builder.create (Array.length positions) in
  Array.iteri (fun point (x, y, z) ->
    Packed.Float3.Builder.set packed point x y z) positions;
  let topology = Topology.Builder.create ~point_count:(Array.length positions) () in
  Array.iter (Topology.Builder.add_open_polyline topology) curves;
  Geometry.create ~positions:(Packed.Float3.Builder.freeze packed)
    ~topology:(Topology.Builder.freeze topology) () |> Result.get_ok

let edge_group name geometry = match Geometry.find_edge_group name geometry with
  | Some group -> group
  | None -> fail ("missing edge group " ^ name)

let edge index a b = Topology_index.find_edge index ~a ~b |> Option.get
let mem_pair geometry group a b =
  let index = Topology_index.create (Geometry.topology geometry) in
  Edge_group.mem (edge index a b) group

let expect_invalid operation message = match operation () with
  | Error error -> check (Error.code error = "invalid_edge_group") message
  | Ok _ -> fail (message ^ ": unexpectedly succeeded")

let star () = geometry
    [|(0., 0., 0.); (1., 0., 0.); (0., 1., 0.); (-1., 0., 0.);
      (4., 0., 0.); (5., 0., 0.)|]
    [|[|0; 1|]; [|0; 2|]; [|0; 3|]; [|4; 5|]|]

let test_incident_pairwise_angles () =
  let source = star () in
  let right_angles = Ops.group_edges ~angle_basis:Ops.Incident_edges
      ~min_angle:(Float.pi /. 2.) ~max_angle:(Float.pi /. 2.)
      ~name:"right_angles" source |> get_ok in
  let right = edge_group "right_angles" right_angles in
  check (Edge_group.cardinality right = 3
      && mem_pair source right 0 1
      && mem_pair source right 0 2
      && mem_pair source right 0 3
      && not (mem_pair source right 4 5))
    "incident-edge inclusive right-angle selection";
  let straight_angles = Ops.group_edges ~angle_basis:Ops.Incident_edges
      ~min_angle:Float.pi ~max_angle:Float.pi ~name:"straight_angles" source
      |> get_ok in
  let straight = edge_group "straight_angles" straight_angles in
  check (Edge_group.cardinality straight = 2
      && mem_pair source straight 0 1
      && mem_pair source straight 0 3
      && not (mem_pair source straight 0 2))
    "incident-edge straight-angle selection"

let test_base_restriction_and_zero_length () =
  let source = geometry
      [|(0., 0., 0.); (1., 0., 0.); (0., 1., 0.)|]
      [|[|0; 1|]; [|0; 2|]; [|0; 0|]|] in
  let selected = Group.init ~owner:Group.Primitive ~name:"selected" 3
      (fun primitive -> primitive = 0) in
  let restricted = Geometry.with_group selected source |> Result.get_ok
      |> Ops.group_edges ~primitives:selected ~angle_basis:Ops.Incident_edges
           ~min_angle:0. ~max_angle:Float.pi ~name:"restricted"
      |> get_ok in
  check (Edge_group.cardinality (edge_group "restricted" restricted) = 0)
    "incident-edge comparison honors primitive restriction on both edges";
  let all = Ops.group_edges ~angle_basis:Ops.Incident_edges
      ~min_angle:0. ~max_angle:Float.pi ~name:"all" source |> get_ok in
  check (Edge_group.cardinality (edge_group "all" all) = 2)
    "incident-edge comparison excludes degenerate self edges"

let test_extreme_coordinates_and_failures () =
  let magnitude = max_float /. 4. in
  let source = geometry
      [|(magnitude, magnitude, magnitude); (-.magnitude, magnitude, magnitude);
        (magnitude, -.magnitude, magnitude)|]
      [|[|0; 1|]; [|0; 2|]|] in
  let selected = Ops.group_edges ~angle_basis:Ops.Incident_edges
      ~min_angle:(Float.pi /. 2.) ~max_angle:(Float.pi /. 2.)
      ~name:"extreme" source |> get_ok |> edge_group "extreme" in
  check (Edge_group.cardinality selected = 2)
    "incident-edge angle normalizes extreme coordinates";
  let length_source = geometry
      [|(max_float, 0., 0.); (-.max_float, 0., 0.)|] [|[|0; 1|]|] in
  let long = Ops.group_edges ~min_length:max_float ~name:"long" length_source
      |> get_ok |> edge_group "long" in
  check (Edge_group.cardinality long = 1)
    "edge length comparison handles distances beyond max_float";
  expect_invalid (fun () -> Ops.group_edges ~angle_basis:Ops.Incident_edges
      ~min_angle:2. ~max_angle:1. source)
    "incident-edge angle rejects reversed bounds";
  let nonfinite = geometry
      [|(0., 0., 0.); (Float.nan, 0., 0.); (0., 1., 0.)|]
      [|[|0; 1|]; [|0; 2|]|] in
  expect_invalid (fun () -> Ops.group_edges ~angle_basis:Ops.Incident_edges
      ~min_angle:0. nonfinite)
    "incident-edge angle rejects non-finite positions";
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.group_edges ~cancel:cancelled ~angle_basis:Ops.Incident_edges
      ~min_angle:0. source with
   | Error error -> check (Error.code error = "cancelled")
       "incident-edge cancellation code"
   | Ok _ -> fail "cancelled incident-edge selection published geometry")

let test_parallel_exactness_and_scale () =
  let source = Ops.grid ~columns:600 ~rows:400 ~size:20. () |> get_ok in
  let run domains = Parallel.run ~domains (fun () ->
    Ops.group_edges ~grain:1_009 ~angle_basis:Ops.Incident_edges
      ~min_angle:(Float.pi /. 2.) ~max_angle:(Float.pi /. 2.)
      ~name:"orthogonal" source |> get_ok) in
  let one = run 1 |> edge_group "orthogonal"
  and four = run 4 |> edge_group "orthogonal" in
  check (Edge_group.length one = Edge_group.length four
      && Edge_group.cardinality one = Edge_group.cardinality four)
    "incident-edge one/four-domain cardinality";
  for edge = 0 to Edge_group.length one - 1 do
    if Edge_group.mem edge one <> Edge_group.mem edge four then
      fail "incident-edge one/four-domain membership differs"
  done;
  check (Edge_group.cardinality one > 0)
    "incident-edge scale fixture selected no edges"

let () =
  test_incident_pairwise_angles ();
  test_base_restriction_and_zero_length ();
  test_extreme_coordinates_and_failures ();
  test_parallel_exactness_and_scale ();
  print_endline "group edge-angle tests passed"
