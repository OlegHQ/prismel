open Rays
open Rdk
open Rdk_test_support

let group owner name geometry = match Geometry.find_group ~owner name geometry with
  | Some group -> group
  | None -> fail ("missing group " ^ name)

let members group =
  let output = ref [] in
  Group.iter (fun element -> output := element :: !output) group;
  List.rev !output

let expect_members expected group message =
  if members group <> expected then fail message

let disconnected ?region () =
  Group_ops.Range_disconnected { region }

let connected ?attributes ?(tolerance = 1e-6) ?collision ?region
    ?(remove_other_regions = true) () =
  Group_ops.Range_connected {
    connectivity_attributes = attributes;
    connectivity_tolerance = tolerance;
    collision;
    region;
    remove_other_regions;
  }

let with_attribute name owner storage geometry =
  let attribute = Attribute.create_owned ~name ~owner storage
      |> function Ok value -> value | Error message -> fail message in
  Geometry.with_attribute attribute geometry
  |> function Ok value -> value | Error message -> fail message

let with_group owner name predicate geometry =
  let count = match owner with
    | Group.Point -> Geometry.point_count geometry
    | Group.Vertex -> Geometry.vertex_count geometry
    | Group.Primitive -> Geometry.primitive_count geometry in
  Geometry.with_group (Group.init ~owner ~name count predicate) geometry
  |> function Ok value -> value | Error message -> fail message

let with_edge_group name ~a ~b geometry =
  let topology = Geometry.topology geometry in
  let index = Topology_index.create topology in
  let selected = Topology_index.find_edge_index index ~a ~b in
  if selected < 0 then fail "missing fixture edge";
  let edge_group = Edge_group.init ~topology ~index ~name
      (fun edge -> edge = selected) in
  Geometry.with_edge_group edge_group geometry
  |> function Ok value -> value | Error message -> fail message

let test_multiple_ranges_parallel_exactness () =
  let source = Plane_generators.grid ~columns:400 ~rows:250 ~size:10. () |> get_ok in
  let point_count = Geometry.point_count source in
  let source = with_attribute "stripe" Attribute.Point
      (Attribute.Int (Array.init point_count (fun point -> point / 10_000)))
      source in
  let rules = [
    { (Group_ops.range_rule
        ~owner:Group_ops.Group_points ~name:"periodic"
        (Group_ops.Range_from_ends { start = 7; end_offset = 9 }))
      with range_filter = Some { select = 3; of_ = 11; offset = 2 } };
    { (Group_ops.range_rule
        ~owner:Group_ops.Group_points ~name:"pieces"
        (Group_ops.Range_start_end { start = 0; end_ = 2 }))
      with range_connectivity = Some (connected ~attributes:"stripe" ()) };
    Group_ops.range_rule ~owner:Group_ops.Group_primitives ~name:"partition"
      (Group_ops.Range_partition { partition = 2; partitions = 7 });
  ] in
  let run domains = Parallel.run ~domains (fun () ->
    Group_ops.ranges ~grain:1_009 ~rules source |> get_ok) in
  let one = run 1 and four = run 4 in
  check (Topology.data_id (Geometry.topology one)
      = Topology.data_id (Geometry.topology four)
      && List.map Group.name (Geometry.groups one)
         = List.map Group.name (Geometry.groups four))
    "Group Ranges parallel output metadata differs";
  List.iter (fun (owner, name) ->
    let left = group owner name one and right = group owner name four in
    check (Bytes.equal (Group.Private.bits_view left)
        (Group.Private.bits_view right))
      ("Group Ranges domain mismatch for " ^ name))
    [Group.Point, "periodic"; Group.Point, "pieces";
     Group.Primitive, "partition"]

let run () =
  test_multiple_ranges_parallel_exactness ();
  print_endline "group range connectivity tests passed"
