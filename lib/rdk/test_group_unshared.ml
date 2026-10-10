open Rays
open Rdk
open Rdk_test_support

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

let test_parallel_exactness_and_scale () =
  let source = Plane_generators.grid ~columns:600 ~rows:400 ~size:20. () |> get_ok in
  let run domains = Parallel.run ~domains (fun () ->
    source
    |> Group_ops.group_unshared ~grain:1_009 ~owner:Group_ops.Group_edges ~name:"border"
    |> get_ok
    |> Group_ops.group_unshared ~grain:1_009 ~owner:Group_ops.Group_points
         ~name:"border_points" |> get_ok
    |> Group_ops.group_unshared ~grain:1_009 ~owner:Group_ops.Group_primitives
         ~name:"border_faces" |> get_ok
    |> Group_ops.group_boundary_components ~grain:1_009 ~prefix:"loop" |> get_ok) in
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

let run () =
  test_parallel_exactness_and_scale ();
  print_endline "group unshared/boundary tests passed"
