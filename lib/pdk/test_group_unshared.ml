open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function
  | Ok value -> value
  | Error error -> fail (Error.to_string error)

let geometry positions primitives =
  let packed = Packed.Float3.Builder.create (Array.length positions) in
  Array.iteri (fun point (x, y, z) ->
    Packed.Float3.Builder.set packed point x y z) positions;
  let topology = Topology.Builder.create ~point_count:(Array.length positions) () in
  Array.iter (fun (kind, points) -> match kind with
    | `Polygon -> Topology.Builder.add_polygon topology points
    | `Open -> Topology.Builder.add_open_polyline topology points) primitives;
  Geometry.create ~positions:(Packed.Float3.Builder.freeze packed)
    ~topology:(Topology.Builder.freeze topology) () |> Result.get_ok

let sample () = geometry
    [|(0.,0.,0.); (1.,0.,0.); (1.,1.,0.); (0.,1.,0.);
      (2.,0.,0.); (3.,0.,0.); (4.,0.,0.); (5.,0.,0.);
      (7.,0.,0.); (8.,0.,0.); (7.5,1.,0.)|]
    [|`Polygon, [|0;1;2|]; `Polygon, [|0;2;3|];
      `Open, [|4;5;6;7|]; `Polygon, [|8;9;10|]|]

let group owner name geometry =
  match Geometry.find_group ~owner name geometry with
  | Some group -> group
  | None -> fail ("missing group " ^ name)

let edge_group name geometry = match Geometry.find_edge_group name geometry with
  | Some group -> group
  | None -> fail ("missing edge group " ^ name)

let members group =
  let output = ref [] in
  Group.iter (fun element -> output := element :: !output) group;
  List.rev !output

let expect_members expected group message =
  check (members group = expected) message

let expect_invalid operation message = match operation () with
  | Error error -> check (Error.code error = "invalid_group") message
  | Ok _ -> fail (message ^ ": unexpectedly succeeded")

let test_unshared_owners_and_curves () =
  let source = sample () in
  let edges = Ops.group_unshared ~owner:Ops.Group_edges ~name:"unshared_edges"
      source |> get_ok in
  check (Edge_group.cardinality (edge_group "unshared_edges" edges) = 10)
    "Group Unshared edge cardinality includes every curve segment";
  let points = Ops.group_unshared ~owner:Ops.Group_points ~name:"unshared_points"
      source |> get_ok in
  expect_members (List.init 11 Fun.id) (group Group.Point "unshared_points" points)
    "Group Unshared point incidence";
  let primitives = Ops.group_unshared ~owner:Ops.Group_primitives
      ~name:"unshared_primitives" source |> get_ok in
  expect_members [0;1;2;3]
    (group Group.Primitive "unshared_primitives" primitives)
    "Group Unshared primitive incidence";
  let index = Topology_index.create (Geometry.topology source) in
  let diagonal = Topology_index.find_edge index ~a:0 ~b:2 |> Option.get in
  check (not (Edge_group.mem diagonal (edge_group "unshared_edges" edges)))
    "Group Unshared selected a shared polygon edge"

let test_unshared_merge_and_failures () =
  let source = sample () in
  let existing = Group.init ~owner:Group.Point ~name:"target" 11
      (fun point -> point = 0 || point = 5) in
  let source = Geometry.with_group existing source |> Result.get_ok in
  let intersection = Ops.group_unshared ~merge:Ops.Group_intersection
      ~owner:Ops.Group_points ~name:"target" source |> get_ok in
  expect_members [0;5] (group Group.Point "target" intersection)
    "Group Unshared intersection";
  let absent = Ops.group_unshared ~merge:Ops.Group_subtract
      ~owner:Ops.Group_points ~name:"absent" source |> get_ok in
  expect_members [] (group Group.Point "absent" absent)
    "Group Unshared absent subtraction identity";
  expect_invalid (fun () -> Ops.group_unshared ~owner:Ops.Group_vertices
      ~name:"bad" source) "Group Unshared rejects vertex output";
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.group_unshared ~cancel:cancelled ~owner:Ops.Group_edges
      ~name:"bad" source with
   | Error error -> check (Error.code error = "cancelled")
       "Group Unshared cancellation code"
   | Ok _ -> fail "cancelled Group Unshared published geometry")

let test_boundary_components () =
  let source = sample () in
  let grouped = Ops.group_boundary_components ~prefix:"rim" source |> get_ok in
  expect_members [0;1;2;3] (group Group.Point "rim__0" grouped)
    "boundary component stable first surface";
  expect_members [8;9;10] (group Group.Point "rim__1" grouped)
    "boundary component stable second surface";
  check (Geometry.find_group ~owner:Group.Point "rim__2" grouped = None)
    "boundary components included an open curve";
  let existing = Group.init ~owner:Group.Point ~name:"rim__0" 11
      (fun point -> point = 4) in
  let unioned = Geometry.with_group existing source |> Result.get_ok
      |> Ops.group_boundary_components ~prefix:"rim" ~conflict:Ops.Name_union
      |> get_ok in
  expect_members [0;1;2;3;4] (group Group.Point "rim__0" unioned)
    "boundary component union conflict";
  expect_invalid (fun () -> Ops.group_boundary_components ~prefix:"rim"
      ~max_groups:1 source) "boundary component group-count preflight";
  expect_invalid (fun () -> Ops.group_boundary_components ~prefix:"rim"
      ~max_payload_bytes:0 source) "boundary component payload preflight";
  let closed = Ops.box ~size:(Vec3.create 1. 1. 1.) () |> get_ok
      |> Ops.fuse ~tolerance:0. ~attributes:Ops.Average_numeric |> get_ok
      |> Ops.group_boundary_components ~prefix:"closed" |> get_ok in
  check (Geometry.find_group ~owner:Group.Point "closed__0" closed = None)
    "closed surface produced a boundary component"

let test_parallel_exactness_and_scale () =
  let source = Ops.grid ~columns:600 ~rows:400 ~size:20. () |> get_ok in
  let run domains = Parallel.run ~domains (fun () ->
    source
    |> Ops.group_unshared ~grain:1_009 ~owner:Ops.Group_edges ~name:"border"
    |> get_ok
    |> Ops.group_unshared ~grain:1_009 ~owner:Ops.Group_points
         ~name:"border_points" |> get_ok
    |> Ops.group_unshared ~grain:1_009 ~owner:Ops.Group_primitives
         ~name:"border_faces" |> get_ok
    |> Ops.group_boundary_components ~grain:1_009 ~prefix:"loop" |> get_ok) in
  let one = run 1 and four = run 4 in
  let compare_group owner name =
    let left = group owner name one and right = group owner name four in
    check (Group.length left = Group.length right) (name ^ " length");
    for element = 0 to Group.length left - 1 do
      if Group.mem element left <> Group.mem element right then
        fail (name ^ " differs by domain count")
    done in
  let left_edges = edge_group "border" one
  and right_edges = edge_group "border" four in
  check (Edge_group.cardinality left_edges = 2_000
      && Edge_group.cardinality right_edges = 2_000)
    "Group Unshared grid boundary edge cardinality";
  for edge = 0 to Edge_group.length left_edges - 1 do
    if Edge_group.mem edge left_edges <> Edge_group.mem edge right_edges then
      fail "Group Unshared edges differ by domain count"
  done;
  compare_group Group.Point "border_points";
  compare_group Group.Primitive "border_faces";
  compare_group Group.Point "loop__0";
  check (Group.cardinality (group Group.Point "loop__0" one) = 2_000)
    "boundary component grid cardinality"

let () =
  test_unshared_owners_and_curves ();
  test_unshared_merge_and_failures ();
  test_boundary_components ();
  test_parallel_exactness_and_scale ();
  print_endline "group unshared/boundary tests passed"
