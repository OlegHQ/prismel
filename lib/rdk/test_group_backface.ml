open Rays
open Rdk
open Rdk_test_support

let group name geometry = match Geometry.find_group ~owner:Group.Primitive name geometry with
  | Some group -> group
  | None -> fail ("missing group " ^ name)

let members group =
  let output = ref [] in
  Group.iter (fun member -> output := member :: !output) group;
  List.rev !output

let expect_members expected group message =
  check (members group = expected) message

let expect_invalid operation message = match operation () with
  | Error error -> check (Error.code error = "invalid_group") message
  | Ok _ -> fail (message ^ ": unexpectedly succeeded")

let test_scale_parallel_exactness () =
  let source = Plane_generators.grid ~columns:600 ~rows:400 ~size:20. () |> get_ok in
  let run domains = Parallel.run ~domains (fun () ->
    Group_ops.group_backface ~grain:1_009 ~viewpoint:(Vec3.create 0. (-10.) 0.)
      ~name:"backfaces" source |> get_ok) in
  let one = run 1 and four = run 4 in
  let one = group "backfaces" one and four = group "backfaces" four in
  check (Group.length one = Group.length four && members one = members four)
    "Group Backface one/four-domain exactness";
  check (Group.cardinality one = Geometry.primitive_count source)
    "Group Backface scale cardinality"

let run () =
  test_scale_parallel_exactness ();
  print_endline "group backface tests passed"
