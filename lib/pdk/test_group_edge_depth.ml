open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function
  | Ok value -> value
  | Error error -> fail (Error.to_string error)

let geometry point_count curves =
  let positions = Packed.Float3.Builder.create point_count in
  for point = 0 to point_count - 1 do
    Packed.Float3.Builder.set positions point (float_of_int point) 0. 0.
  done;
  let topology = Topology.Builder.create ~point_count () in
  Array.iter (Topology.Builder.add_open_polyline topology) curves;
  Geometry.create ~positions:(Packed.Float3.Builder.freeze positions)
    ~topology:(Topology.Builder.freeze topology) () |> Result.get_ok

let point_group name geometry =
  match Geometry.find_group ~owner:Group.Point name geometry with
  | Some group -> group
  | None -> fail ("missing point group " ^ name)

let members group =
  let output = ref [] in
  Group.iter (fun point -> output := point :: !output) group;
  List.rev !output

let expect_members expected group message =
  check (members group = expected) message

let expect_invalid operation message = match operation () with
  | Error error -> check (Error.code error = "invalid_group") message
  | Ok _ -> fail (message ^ ": unexpectedly succeeded")

let sample () =
  let source = geometry 13
      [|[|0; 1; 2; 3; 4; 5; 6; 7; 8|]; [|9; 10; 11|]|] in
  let seed = Group.init ~owner:Group.Point ~name:"seed" 13
      (fun point -> point = 4 || point = 10 || point = 12) in
  Geometry.with_group seed source |> Result.get_ok

let test_depth_and_disconnected_components () =
  let source = sample () in
  let zero = Ops.group_edge_depth ~depth:0 ~point_group:"seed" ~name:"zero"
      source |> get_ok in
  expect_members [4; 10; 12] (point_group "zero" zero)
    "Group Edge Depth includes only seeds at depth zero";
  let two = Ops.group_edge_depth ~depth:2 ~point_group:"seed" ~name:"two"
      source |> get_ok in
  expect_members [2; 3; 4; 5; 6; 9; 10; 11; 12] (point_group "two" two)
    "Group Edge Depth bounded multi-source distance";
  let flooded = Ops.group_edge_depth ~depth:max_int ~point_group:"seed"
      ~name:"flooded" source |> get_ok in
  expect_members (List.init 13 Fun.id) (point_group "flooded" flooded)
    "Group Edge Depth terminates after exhausting seeded components";
  expect_members [4; 10; 12] (point_group "seed" source)
    "Group Edge Depth mutated its source group"

let test_merge_algebra () =
  let source = sample () in
  let existing = Group.init ~owner:Group.Point ~name:"target" 13
      (fun point -> point = 0 || point = 3 || point = 9) in
  let source = Geometry.with_group existing source |> Result.get_ok in
  let intersection = Ops.group_edge_depth ~merge:Ops.Group_intersection
      ~depth:1 ~point_group:"seed" ~name:"target" source |> get_ok in
  expect_members [3; 9] (point_group "target" intersection)
    "Group Edge Depth intersection";
  let union = Ops.group_edge_depth ~merge:Ops.Group_union ~depth:1
      ~point_group:"seed" ~name:"target" source |> get_ok in
  expect_members [0; 3; 4; 5; 9; 10; 11; 12] (point_group "target" union)
    "Group Edge Depth union";
  let subtract = Ops.group_edge_depth ~merge:Ops.Group_subtract ~depth:1
      ~point_group:"seed" ~name:"target" source |> get_ok in
  expect_members [0] (point_group "target" subtract)
    "Group Edge Depth subtraction";
  let absent_intersection = Ops.group_edge_depth
      ~merge:Ops.Group_intersection ~depth:1 ~point_group:"seed"
      ~name:"absent_intersection" source |> get_ok in
  expect_members [] (point_group "absent_intersection" absent_intersection)
    "Group Edge Depth absent intersection identity";
  let absent_subtract = Ops.group_edge_depth ~merge:Ops.Group_subtract
      ~depth:1 ~point_group:"seed" ~name:"absent_subtract" source |> get_ok in
  expect_members [] (point_group "absent_subtract" absent_subtract)
    "Group Edge Depth absent subtraction identity";
  let in_place = Ops.group_edge_depth ~depth:1 ~point_group:"seed" ~name:"seed"
      source |> get_ok in
  expect_members [3; 4; 5; 9; 10; 11; 12] (point_group "seed" in_place)
    "Group Edge Depth same-name replacement"

let test_failures_and_cancellation () =
  let source = sample () in
  expect_invalid (fun () -> Ops.group_edge_depth ~depth:(-1)
      ~point_group:"seed" ~name:"bad" source)
    "Group Edge Depth rejects negative depth";
  expect_invalid (fun () -> Ops.group_edge_depth ~depth:1
      ~point_group:"missing" ~name:"bad" source)
    "Group Edge Depth rejects missing seed group";
  expect_invalid (fun () -> Ops.group_edge_depth ~depth:1
      ~point_group:"" ~name:"bad" source)
    "Group Edge Depth rejects empty seed name";
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.group_edge_depth ~cancel:cancelled ~depth:1
      ~point_group:"seed" ~name:"bad" source with
   | Error error -> check (Error.code error = "cancelled")
       "Group Edge Depth cancellation code"
   | Ok _ -> fail "cancelled Group Edge Depth published geometry")

let test_parallel_exactness_and_scale () =
  let source = Ops.grid ~columns:600 ~rows:400 ~size:20. () |> get_ok in
  let count = Geometry.point_count source and width = 601 in
  let seed = Group.init ~grain:1_009 ~owner:Group.Point ~name:"center" count
      (fun point -> point = (200 * width) + 300) in
  let source = Geometry.with_group seed source |> Result.get_ok in
  let run domains = Parallel.run ~domains (fun () ->
    Ops.group_edge_depth ~grain:1_009 ~depth:64 ~point_group:"center"
      ~name:"grown" source |> get_ok) in
  let one = run 1 |> point_group "grown"
  and four = run 4 |> point_group "grown" in
  check (Group.length one = Group.length four
      && Group.cardinality one = Group.cardinality four)
    "Group Edge Depth one/four-domain cardinality";
  for point = 0 to Group.length one - 1 do
    if Group.mem point one <> Group.mem point four then
      fail "Group Edge Depth one/four-domain membership differs"
  done;
  check (Group.cardinality one > 1 && Group.cardinality one < count)
    "Group Edge Depth scale fixture cardinality"

let () =
  test_depth_and_disconnected_components ();
  test_merge_algebra ();
  test_failures_and_cancellation ();
  test_parallel_exactness_and_scale ();
  print_endline "group edge-depth tests passed"
