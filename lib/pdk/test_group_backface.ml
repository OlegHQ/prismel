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

let sample () = geometry
    [|(-1., -1., 0.); (1., -1., 0.); (0., 1., 0.);
      (-1., -1., 2.); (0., 1., 2.); (1., -1., 2.);
      (0., -1., 3.); (0., 1., 3.); (0., 0., 5.);
      (-1., 0., 7.); (1., 0., 7.)|]
    [|`Polygon, [|0; 1; 2|]; `Polygon, [|3; 4; 5|];
      `Polygon, [|6; 7; 8|]; `Open, [|9; 10|]|]

let test_winding_viewpoint_and_edge_on () =
  let source = sample () in
  let above = Ops.group_backface ~viewpoint:(Vec3.create 0. 0. 10.)
      ~name:"above" source |> get_ok in
  expect_members [1] (group "above" above)
    "Group Backface winding, curve, and edge-on behavior";
  let below = Ops.group_backface ~viewpoint:(Vec3.create 0. 0. (-10.))
      ~name:"below" source |> get_ok in
  expect_members [0] (group "below" below)
    "Group Backface viewpoint reversal"

let test_extreme_coordinates () =
  let magnitude = max_float /. 4. in
  let source = geometry
      [|(magnitude, magnitude, magnitude); (-.magnitude, magnitude, magnitude);
        (magnitude, -.magnitude, magnitude)|]
      [|`Polygon, [|0; 1; 2|]|] in
  let front = Ops.group_backface ~viewpoint:(Vec3.create 0. 0. max_float)
      ~name:"front" source |> get_ok in
  expect_members [] (group "front" front)
    "Group Backface overflow-safe extreme front face";
  let back = Ops.group_backface ~viewpoint:(Vec3.create 0. 0. (-.max_float))
      ~name:"back" source |> get_ok in
  expect_members [0] (group "back" back)
    "Group Backface overflow-safe extreme back face"

let test_base_merge_and_failures () =
  let source = sample () in
  let base = Group.init ~grain:1 ~owner:Group.Primitive ~name:"base" 4
      (fun primitive -> primitive = 0) in
  let visible = Group.init ~grain:1 ~owner:Group.Primitive ~name:"visible" 4
      (fun _ -> true) in
  let source = Geometry.with_group base source |> Result.get_ok
      |> Geometry.with_group visible |> Result.get_ok in
  let based = Ops.group_backface ~base:"base"
      ~viewpoint:(Vec3.create 0. 0. 10.) ~name:"based" source |> get_ok in
  expect_members [] (group "based" based)
    "Group Backface exact primitive base restriction";
  let visible = Ops.group_backface ~merge:Ops.Group_subtract
      ~viewpoint:(Vec3.create 0. 0. 10.) ~name:"visible" source |> get_ok in
  expect_members [0; 2; 3] (group "visible" visible)
    "Group Backface subtracts from an existing criteria group";
  let absent_intersection = Ops.group_backface ~merge:Ops.Group_intersection
      ~viewpoint:(Vec3.create 0. 0. 10.) ~name:"absent_intersection" source
      |> get_ok in
  check (Group.cardinality (group "absent_intersection" absent_intersection) = 0)
    "Group Backface absent destination intersection identity";
  let absent_subtract = Ops.group_backface ~merge:Ops.Group_subtract
      ~viewpoint:(Vec3.create 0. 0. 10.) ~name:"absent_subtract" source
      |> get_ok in
  check (Group.cardinality (group "absent_subtract" absent_subtract) = 0)
    "Group Backface absent destination subtraction identity";
  expect_invalid (fun () -> Ops.group_backface
      ~viewpoint:(Vec3.create Float.nan 0. 0.) ~name:"bad" source)
    "Group Backface rejects a non-finite viewpoint";
  expect_invalid (fun () -> Ops.group_backface ~base:"missing"
      ~viewpoint:Vec3.zero ~name:"bad" source)
    "Group Backface rejects a missing base";
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.group_backface ~cancel:cancelled ~viewpoint:Vec3.zero
      ~name:"bad" source with
   | Error error -> check (Error.code error = "cancelled")
       "Group Backface cancellation code"
   | Ok _ -> fail "cancelled Group Backface published geometry")

let test_scale_parallel_exactness () =
  let source = Ops.grid ~columns:600 ~rows:400 ~size:20. () |> get_ok in
  let run domains = Parallel.run ~domains (fun () ->
    Ops.group_backface ~grain:1_009 ~viewpoint:(Vec3.create 0. (-10.) 0.)
      ~name:"backfaces" source |> get_ok) in
  let one = run 1 and four = run 4 in
  let one = group "backfaces" one and four = group "backfaces" four in
  check (Group.length one = Group.length four && members one = members four)
    "Group Backface one/four-domain exactness";
  check (Group.cardinality one = Geometry.primitive_count source)
    "Group Backface scale cardinality"

let () =
  test_winding_viewpoint_and_edge_on ();
  test_extreme_coordinates ();
  test_base_merge_and_failures ();
  test_scale_parallel_exactness ();
  print_endline "group backface tests passed"
