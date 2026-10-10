open Rays
open Rdk
open Rdk_test_support

let get_group_ok = function
  | Ok value -> value
  | Error message -> fail message

let point_cloud count =
  Line_geometry.points (Array.init count (fun point -> float_of_int point, 0., 0.))

let owner_count geometry = function
  | Group.Point -> Geometry.point_count geometry
  | Group.Vertex -> Geometry.vertex_count geometry
  | Group.Primitive -> Geometry.primitive_count geometry

let with_group owner name predicate geometry =
  Geometry.with_group
    (Group.init ~grain:1 ~owner ~name (owner_count geometry owner) predicate)
    geometry
  |> function Ok geometry -> geometry | Error message -> fail message

let with_ordered_group owner name elements geometry =
  let group = Group.ordered ~owner ~name ~length:(owner_count geometry owner)
      elements |> get_group_ok in
  Geometry.with_group group geometry
  |> function Ok geometry -> geometry | Error message -> fail message

let with_edge_group name predicate geometry =
  let topology = Geometry.topology geometry in
  let index = Topology_index.create topology in
  Geometry.with_edge_group
    (Edge_group.init ~grain:1 ~topology ~index ~name predicate) geometry
  |> function Ok geometry -> geometry | Error message -> fail message

let with_int owner name values geometry =
  let attribute = Attribute.create_owned ~owner ~name (Attribute.Int values)
    |> function Ok value -> value | Error message -> fail message in
  Geometry.with_attribute attribute geometry
  |> function Ok geometry -> geometry | Error message -> fail message

let with_text owner name values geometry =
  let attribute = Attribute.create_owned ~owner ~name (Attribute.Text values)
    |> function Ok value -> value | Error message -> fail message in
  Geometry.with_attribute attribute geometry
  |> function Ok geometry -> geometry | Error message -> fail message

let ordinary owner name geometry =
  match Geometry.find_group ~owner name geometry with
  | Some group -> group
  | None -> fail ("missing group " ^ name)

let edge name geometry =
  match Geometry.find_edge_group name geometry with
  | Some group -> group
  | None -> fail ("missing edge group " ^ name)

let group_members group =
  let members = ref [] in
  Group.iter (fun element -> members := element :: !members) group;
  List.rev !members

let ordered_group_members group =
  let members = ref [] in
  Group.iter_ordered (fun element -> members := element :: !members) group;
  List.rev !members

let edge_members group =
  let members = ref [] in
  Edge_group.iter (fun element -> members := element :: !members) group;
  List.rev !members

let expect_members expected group message =
  check (group_members group = expected) message

let same_group left right =
  Group.owner left = Group.owner right && Group.length left = Group.length right
  && group_members left = group_members right
  && Group.ordered_elements left = Group.ordered_elements right

let test_ordered_group_core () =
  let left = Group.ordered ~owner:Group.Point ~name:"left" ~length:6
      [|3; 1; 4|] |> get_group_ok in
  let right = Group.ordered ~owner:Group.Point ~name:"right" ~length:6
      [|4; 2; 1|] |> get_group_ok in
  check (group_members left = [1; 3; 4])
    "ordered group preserves sorted legacy iteration";
  check (ordered_group_members left = [3; 1; 4])
    "ordered group preserves explicit traversal";
  check (Group.is_ordered left) "ordered group reports its order plane";
  let exposed = Option.get (Group.ordered_elements left) in
  exposed.(0) <- 0;
  check (ordered_group_members left = [3; 1; 4])
    "ordered group returns a defensive order copy";
  check (Group.payload_bytes left
      = ((Group.length left + 7) / 8)
        + (3 * (Sys.word_size / 8)))
    "ordered group accounts for order payload storage";
  let renamed = Group.with_name "renamed" left in
  check (ordered_group_members renamed = [3; 1; 4]
      && Group.data_id renamed <> Group.data_id left)
    "group rename preserves order with a fresh payload identity";
  let union = Group.union left right |> get_group_ok in
  check (ordered_group_members union = [3; 1; 4; 2])
    "ordered union follows left order then unseen right members";
  let intersection = Group.intersection left right |> get_group_ok in
  check (ordered_group_members intersection = [1; 4])
    "ordered intersection follows the left order";
  let difference = Group.difference left right |> get_group_ok in
  check (ordered_group_members difference = [3])
    "ordered difference preserves surviving left order";
  let xor = Group.symmetric_difference left right |> get_group_ok in
  check (ordered_group_members xor = [3; 2])
    "ordered symmetric difference preserves deterministic operand order";
  let complement = Group.complement left in
  check (not (Group.is_ordered complement)
      && group_members complement = [0; 2; 5])
    "group complement drops an order that cannot describe new members";
  (match Group.ordered ~owner:Group.Point ~name:"bad" ~length:4 [|1; 1|] with
   | Error _ -> ()
   | Ok _ -> fail "ordered group accepted duplicate elements");
  (match Group.ordered ~owner:Group.Point ~name:"bad" ~length:4 [|4|] with
   | Error _ -> ()
   | Ok _ -> fail "ordered group accepted an out-of-range element");
  (match Group.ordered ~owner:Group.Point ~name:" " ~length:4 [||] with
   | Error _ -> ()
   | Ok _ -> fail "ordered group accepted an empty name")

let test_ordered_group_topology_remap () =
  let source = point_cloud 6
      |> with_ordered_group Group.Point "path" [|4; 1; 5|] in
  let sorted = Ordering.sort ~grain:1 ~owner:Ordering.Points ~key:Ordering.Reverse source
      |> get_ok in
  check (ordered_group_members (ordinary Group.Point "path" sorted)
      = [1; 4; 0])
    "point reorder remaps explicit group order by element ancestry";
  let remove = Group.init ~grain:1 ~owner:Group.Point ~name:"remove" 6
      (fun point -> point = 1) in
  let deleted = Deletion.delete ~grain:1 remove source |> get_ok in
  check (ordered_group_members (ordinary Group.Point "path" deleted)
      = [3; 4])
    "point deletion filters and remaps explicit group order";
  let duplicated = Instance_copy.duplicate ~grain:1 ~copies:1 source |> get_ok in
  check (ordered_group_members (ordinary Group.Point "path" duplicated)
      = [4; 1; 5; 10; 7; 11])
    "duplicate preserves explicit order in copy-major order";
  let merged = Mesh_merge.run ~grain:1 [source; source] |> get_ok in
  check (ordered_group_members (ordinary Group.Point "path" merged)
      = [4; 1; 5; 10; 7; 11])
    "merge concatenates explicit group order by input";
  let fuse_source = Line_geometry.points
      [|(0., 0., 0.); (0., 0., 0.); (1., 0., 0.); (2., 0., 0.)|]
      |> with_ordered_group Group.Point "path" [|1; 0; 3|] in
  let fused = Fuse_grid.fuse ~grain:1 ~tolerance:0. fuse_source |> get_ok in
  check (ordered_group_members (ordinary Group.Point "path" fused) = [0; 2])
    "fuse collapses duplicate ordered members at first sequence occurrence"

let test_parallel_exactness_and_cancellation () =
  let base = Plane_generators.grid ~columns:500 ~rows:300 ~size:20. () |> get_ok in
  let width = 501 in
  let source = base
      |> with_group Group.Point "stripe_a"
        (fun point -> point mod width = width / 3)
      |> with_group Group.Point "stripe_b"
        (fun point -> point mod width = (2 * width) / 3)
      |> with_int Attribute.Point "id"
        (Array.init (Geometry.point_count base) Fun.id) in
  let target = base |> with_int Attribute.Point "id"
      (Array.init (Geometry.point_count base) (fun index ->
        Geometry.point_count base - index - 1)) in
  let run domains = Parallel.run ~domains (fun () ->
    let ranged = Group_ops.range ~grain:257 ~owner:Group_ops.Group_points
        ~name:"bands" ~filter:{ select = 5; of_ = 13; offset = 3 }
        (Group_ops.Range_from_ends { start = 17; end_offset = 23 }) source |> get_ok in
    let combined = Group_ops.combine ~grain:257 ~owner:Group_ops.Group_points
        ~name:"selection" ~base:{ pattern = "stripe_*"; inverted = false }
        ~steps:[{ operation = Group_ops.Group_xor;
          operand = { pattern = "bands"; inverted = false } }] ranged |> get_ok in
    Group_ops.copy ~grain:257 ~rules:[
      { copy_owner = Group_ops.Group_points; copy_pattern = "selection";
        copy_prefix = "copied_"; match_attribute = Some "id" }]
      ~source:combined ~target () |> get_ok) in
  let one = run 1 and four = run 4 in
  check (same_group (ordinary Group.Point "copied_selection" one)
      (ordinary Group.Point "copied_selection" four))
    "Group Range/Combine/Copy one/four-domain exactness";
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Group_ops.range ~cancel:cancelled ~owner:Group_ops.Group_points ~name:"x"
      (Group_ops.Range_start_end { start = 0; end_ = 100 }) source with
   | Error error -> check (Error.code error = "cancelled")
       "Group Range cancellation code"
   | Ok _ -> fail "cancelled Group Range published geometry");
  (match Group_ops.copy ~cancel:cancelled ~source ~target () with
   | Error error -> check (Error.code error = "cancelled")
       "Group Copy cancellation code"
   | Ok _ -> fail "cancelled Group Copy published geometry")

let transfer_rule owner pattern prefix = {
  Group_ops.transfer_owner = owner;
  transfer_pattern = pattern;
  transfer_prefix = prefix;
}

let curve_mesh positions curves =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:(Array.map (fun (x, _, _) -> x) positions)
      ~y:(Array.map (fun (_, y, _) -> y) positions)
      ~z:(Array.map (fun (_, _, z) -> z) positions) in
  let topology = Tb.create ~point_count:(Packed.Float3.length positions) () in
  Array.iter (Tb.add_open_polyline topology) curves;
  Geometry.create ~positions ~topology:(Tb.freeze topology) ()
  |> function Ok geometry -> geometry | Error message -> fail message

let test_transfer_parallel_exactness () =
  let source = Plane_generators.grid ~columns:100 ~rows:80 ~size:20. () |> get_ok in
  let source = source
      |> with_group Group.Point "point_band" (fun point -> point mod 101 < 7)
      |> with_ordered_group Group.Point "ordered_seed" [|404; 5; 8_000; 2|]
      |> with_group Group.Primitive "face_band" (fun primitive -> primitive mod 19 < 3)
      |> with_edge_group "edge_band" (fun edge -> edge mod 23 < 2) in
  let target = Transform_ops.transform ~grain:257
      (Mat4.translation (Vec3.create 0.0001 0. 0.0001)) source in
  let rules = [transfer_rule Group_ops.Group_points "point_band" "mapped_";
    transfer_rule Group_ops.Group_points "ordered_seed" "mapped_";
    transfer_rule Group_ops.Group_primitives "face_band" "mapped_";
    transfer_rule Group_ops.Group_edges "edge_band" "mapped_"] in
  let run domains = Parallel.run ~domains (fun () ->
    Group_ops.transfer ~grain:257 ~distance:0.01 ~rules
      ~conflict:Group_ops.Copy_overwrite ~source ~target () |> get_ok) in
  let one = run 1 and four = run 4 in
  check (same_group (ordinary Group.Point "mapped_point_band" one)
      (ordinary Group.Point "mapped_point_band" four))
    "Group Transfer point one/four-domain exactness";
  check (same_group (ordinary Group.Primitive "mapped_face_band" one)
      (ordinary Group.Primitive "mapped_face_band" four))
    "Group Transfer primitive one/four-domain exactness";
  check (same_group (ordinary Group.Point "mapped_ordered_seed" one)
      (ordinary Group.Point "mapped_ordered_seed" four))
    "Group Transfer ordered point one/four-domain exactness";
  check (edge_members (edge "mapped_edge_band" one)
      = edge_members (edge "mapped_edge_band" four))
    "Group Transfer edge one/four-domain exactness";
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Group_ops.transfer ~cancel:cancelled ~rules ~source ~target () with
   | Error error -> check (Error.code error = "cancelled")
       "Group Transfer cancellation code"
   | Ok _ -> fail "cancelled Group Transfer published geometry")

let run () =
  test_ordered_group_core ();
  test_ordered_group_topology_remap ();
  test_parallel_exactness_and_cancellation ();
  test_transfer_parallel_exactness ();
  print_endline "group catalog tests passed"
