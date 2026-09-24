open Pdk

module Constraints = Boolean_kernel.Constraints
module Coplanar = Boolean_kernel.Coplanar
module Refinement = Boolean_kernel.Refinement
module Coincident = Boolean_kernel.Coincident

let fail format = Printf.ksprintf failwith format
let check condition message = if not condition then fail "%s" message
let get = function Ok value -> value | Error error -> fail "%s" (Error.to_string error)
let get_string = function Ok value -> value | Error message -> fail "%s" message

let geometry points triangles =
  let count = Array.length points in
  let x = Array.init count (fun point -> let x, _, _ = points.(point) in x)
  and y = Array.init count (fun point -> let _, y, _ = points.(point) in y)
  and z = Array.init count (fun point -> let _, _, z = points.(point) in z) in
  let topology = Topology.polygons_owned ~point_count:count
      ~vertex_points:triangles
      ~primitive_offsets:(Array.init ((Array.length triangles / 3) + 1)
        (fun primitive -> primitive * 3)) |> get_string in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> get_string

let pipeline left right =
  let constraints = Constraints.build ~grain:1 ~left ~right () |> get in
  let coplanar = Coplanar.build ~grain:1 constraints |> get in
  let refinement = Refinement.build ~coplanar ~grain:1 constraints |> get in
  constraints, coplanar, refinement,
  Coincident.build constraints coplanar refinement |> get

let members value group =
  let first, last = Coincident.member_range value group in
  Array.init (last - first) (fun offset ->
      let member = first + offset in
      Coincident.member_side value member,
      Coincident.member_face value member,
      Coincident.member_triangle value member,
      Coincident.member_winding value member)

let triangle points = geometry points [|0;1;2|]

let test_identical_winding () =
  let points = [|0.,0.,0.; 2.,0.,0.; 0.,2.,0.|] in
  let _, _, _, value = pipeline (triangle points) (triangle points) in
  check (Coincident.group_count value = 1) "identical facets were not grouped";
  check (members value 0 = [|
      Coincident.Left, 0, 0, 1;
      Coincident.Right, 0, 0, 1;
    |]) "same-winding facet contributions are wrong"

let test_opposite_winding () =
  let left = triangle [|0.,0.,0.; 2.,0.,0.; 0.,2.,0.|]
  and right = triangle [|0.,2.,0.; 2.,0.,0.; 0.,0.,0.|] in
  let _, _, _, value = pipeline left right in
  check (Coincident.group_count value = 1) "opposite facets were not grouped";
  check (members value 0 = [|
      Coincident.Left, 0, 0, 1;
      Coincident.Right, 0, 0, -1;
    |]) "opposite-winding contribution was not retained"

let test_partial_overlap () =
  let left = triangle [|0.,0.,0.; 4.,0.,0.; 2.,4.,0.|]
  and right = triangle [|0.,3.,0.; 4.,3.,0.; 2.,-1.,0.|] in
  let _, _, _, value = pipeline left right in
  check (Coincident.group_count value = 4)
    "six-edge overlap should contain four identical refined facets";
  for group = 0 to Coincident.group_count value - 1 do
    let group_members = members value group in
    check (Array.length group_members = 2) "overlap facet lost an operand owner";
    let left_side, _, _, left_winding = group_members.(0)
    and right_side, _, _, right_winding = group_members.(1) in
    check (left_side = Coincident.Left && right_side = Coincident.Right
        && left_winding = 1 && right_winding = -1)
      "overlap facet ownership or winding is wrong"
  done

let test_duplicate_contributions () =
  let points = [|0.,0.,0.; 2.,0.,0.; 0.,2.,0.|] in
  let left = triangle points
  and right = geometry
      [|0.,0.,0.; 2.,0.,0.; 0.,2.,0.;
        0.,0.,0.; 2.,0.,0.; 0.,2.,0.|]
      [|0;1;2; 3;4;5|] in
  let _, _, _, value = pipeline left right in
  check (Coincident.group_count value = 1) "duplicate facets split into groups";
  check (Array.length (members value 0) = 3)
    "duplicate coincident contribution was discarded"

let signature value =
  Array.init (Coincident.group_count value) (fun group -> members value group)

let test_domain_exactness () =
  let left = triangle [|0.,0.,0.; 4.,0.,0.; 2.,4.,0.|]
  and right = triangle [|0.,3.,0.; 4.,3.,0.; 2.,-1.,0.|] in
  let run domains = Prismel.Parallel.run ~domains (fun () ->
      let _, _, _, value = pipeline left right in signature value) in
  if run 1 <> run 4 then fail "coincident groups differ between domain counts"

let test_cancellation () =
  let left = triangle [|0.,0.,0.; 2.,0.,0.; 0.,2.,0.|]
  and right = triangle [|0.,0.,0.; 2.,0.,0.; 0.,2.,0.|] in
  let constraints, coplanar, refinement, _ = pipeline left right in
  let cancel = Cancel.create () in Cancel.cancel cancel;
  match Coincident.build ~cancel constraints coplanar refinement with
  | Error error when Error.code error = "cancelled" -> ()
  | Error error -> fail "unexpected cancellation error: %s" (Error.to_string error)
  | Ok _ -> fail "cancelled coincident grouping completed"

let () =
  test_identical_winding ();
  test_opposite_winding ();
  test_partial_overlap ();
  test_duplicate_contributions ();
  test_domain_exactness ();
  test_cancellation ()
