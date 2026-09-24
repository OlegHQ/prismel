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
    [|(0., 0., 0.); (1., 0., 0.); (1., 0., 1.); (0., 0., 1.);
      (2., 0., 0.); (3., 0., 0.); (3., 0.2, 1.); (2., 0., 1.);
      (4., 0., 0.); (5., 0., 0.); (6., 0., 0.); (7., 0., 0.);
      (8., 0., 0.); (9., 0., 0.)|]
    [|`Polygon, [|0; 1; 2; 3|]; `Polygon, [|4; 5; 6; 7|];
      `Polygon, [|8; 9; 10; 11|]; `Open, [|12; 13|]|]

let test_tolerance_and_primitive_kind () =
  let source = sample () in
  let selected = Ops.group_non_planar ~tolerance:0.05 ~name:"warped" source
      |> get_ok in
  expect_members [1] (group "warped" selected)
    "Group Non-Planar selects warped polygon only";
  let tolerant = Ops.group_non_planar ~tolerance:0.25 ~name:"tolerant" source
      |> get_ok in
  expect_members [] (group "tolerant" tolerant)
    "Group Non-Planar absolute tolerance";
  let exact = Ops.group_non_planar ~tolerance:0. ~name:"exact" source |> get_ok in
  expect_members [1] (group "exact" exact)
    "Group Non-Planar exact planar and collinear handling"

let test_stable_support_plane () =
  let source = geometry
      [|(0., 0., 0.); (1., 0., 0.); (2., 0., 0.); (2., 0., 1.);
        (0., 0.1, 1.)|]
      [|`Polygon, [|0; 1; 2; 3; 4|]|] in
  let selected = Ops.group_non_planar ~tolerance:0.01 ~name:"stable" source
      |> get_ok in
  expect_members [0] (group "stable" selected)
    "Group Non-Planar does not depend on a collinear first triple"

let test_triangle_is_planar () =
  let source = geometry
      [|(0.13, -0.71, 0.29); (2.17, 1.03, -0.41); (-1.11, 0.37, 3.07)|]
      [|`Polygon, [|0; 1; 2|]|] in
  let selected = Ops.group_non_planar ~tolerance:0. ~name:"triangles" source
      |> get_ok in
  expect_members [] (group "triangles" selected)
    "Group Non-Planar never classifies a triangle as non-planar"

let test_extreme_coordinates () =
  let magnitude = max_float /. 4. in
  let source = geometry
      [|(magnitude, magnitude, magnitude); (-.magnitude, magnitude, magnitude);
        (magnitude, -.magnitude, magnitude); (-.magnitude, -.magnitude, 0.)|]
      [|`Polygon, [|0; 1; 2; 3|]|] in
  let selected = Ops.group_non_planar ~tolerance:(magnitude /. 8.)
      ~name:"extreme" source |> get_ok in
  expect_members [0] (group "extreme" selected)
    "Group Non-Planar overflow-safe extreme coordinates"

let test_base_merge_and_failures () =
  let source = sample () in
  let base = Group.init ~grain:1 ~owner:Group.Primitive ~name:"base" 4
      (fun primitive -> primitive = 0) in
  let existing = Group.init ~grain:1 ~owner:Group.Primitive ~name:"selection" 4
      (fun primitive -> primitive = 2) in
  let source = Geometry.with_group base source |> Result.get_ok
      |> Geometry.with_group existing |> Result.get_ok in
  let based = Ops.group_non_planar ~base:"base" ~tolerance:0.01
      ~name:"based" source |> get_ok in
  expect_members [] (group "based" based)
    "Group Non-Planar exact base restriction";
  let unioned = Ops.group_non_planar ~merge:Ops.Group_union ~tolerance:0.01
      ~name:"selection" source |> get_ok in
  expect_members [1; 2] (group "selection" unioned)
    "Group Non-Planar additive union merge";
  let absent_intersection = Ops.group_non_planar
      ~merge:Ops.Group_intersection ~tolerance:0.01
      ~name:"absent_intersection" source |> get_ok in
  check (Group.cardinality (group "absent_intersection" absent_intersection) = 0)
    "Group Non-Planar absent destination intersection identity";
  let absent_subtract = Ops.group_non_planar ~merge:Ops.Group_subtract
      ~tolerance:0.01 ~name:"absent_subtract" source |> get_ok in
  check (Group.cardinality (group "absent_subtract" absent_subtract) = 0)
    "Group Non-Planar absent destination subtraction identity";
  expect_invalid (fun () -> Ops.group_non_planar ~tolerance:(-0.1)
      ~name:"bad" source) "Group Non-Planar rejects negative tolerance";
  expect_invalid (fun () -> Ops.group_non_planar ~base:"missing"
      ~tolerance:0. ~name:"bad" source) "Group Non-Planar rejects missing base";
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.group_non_planar ~cancel:cancelled ~tolerance:0. ~name:"bad"
      source with
   | Error error -> check (Error.code error = "cancelled")
       "Group Non-Planar cancellation code"
   | Ok _ -> fail "cancelled Group Non-Planar published geometry")

let quad_strip count =
  let point_count = count * 4 in
  let positions = Packed.Float3.Builder.create point_count
  and topology = Topology.Builder.create ~point_count
      ~vertex_capacity:point_count ~primitive_capacity:count () in
  for primitive = 0 to count - 1 do
    let point = primitive * 4 and x = float_of_int primitive *. 1.25 in
    let warp = if primitive mod 3 = 0 then 0.125 else 0. in
    Packed.Float3.Builder.set positions point x 0. 0.;
    Packed.Float3.Builder.set positions (point + 1) (x +. 1.) 0. 0.;
    Packed.Float3.Builder.set positions (point + 2) (x +. 1.) warp 1.;
    Packed.Float3.Builder.set positions (point + 3) x 0. 1.;
    Topology.Builder.add_polygon topology
      [|point; point + 1; point + 2; point + 3|]
  done;
  Geometry.create ~positions:(Packed.Float3.Builder.freeze positions)
    ~topology:(Topology.Builder.freeze topology) () |> Result.get_ok

let test_scale_parallel_exactness () =
  let source = quad_strip 80_003 in
  let run domains = Parallel.run ~domains (fun () ->
    Ops.group_non_planar ~grain:1_009 ~tolerance:0.01 ~name:"warped" source
    |> get_ok) in
  let one = run 1 and four = run 4 in
  let one = group "warped" one and four = group "warped" four in
  check (Group.length one = Group.length four && members one = members four)
    "Group Non-Planar one/four-domain exactness";
  check (Group.cardinality one = 26_668)
    "Group Non-Planar scale cardinality"

let () =
  test_tolerance_and_primitive_kind ();
  test_stable_support_plane ();
  test_triangle_is_planar ();
  test_extreme_coordinates ();
  test_base_merge_and_failures ();
  test_scale_parallel_exactness ();
  print_endline "group non-planar tests passed"
