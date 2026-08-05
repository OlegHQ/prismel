open Pdk

module Constraints = Boolean_kernel.Constraints
module Coplanar = Boolean_kernel.Coplanar
module Refinement = Boolean_kernel.Refinement
module Complex = Boolean_kernel.Complex
module Radial = Boolean_kernel.Radial
module Weiler = Boolean_kernel.Weiler
module Cells = Boolean_kernel.Cells

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

let tetra ~origin:(ox,oy,oz) size = geometry
    [|ox,oy,oz; ox+.size,oy,oz; ox,oy+.size,oz; ox,oy,oz+.size|]
    [|0;2;1; 0;1;3; 1;2;3; 2;0;3|]

let tetra_batch count shift =
  let points = Array.make (count * 4) (0., 0., 0.)
  and triangles = Array.make (count * 12) 0 in
  let local = [|0;2;1; 0;1;3; 1;2;3; 2;0;3|] in
  for item = 0 to count - 1 do
    let point = item * 4 and x = (float_of_int item *. 6.) +. shift in
    points.(point) <- x, 0., 0.;
    points.(point + 1) <- x +. 1., 0., 0.;
    points.(point + 2) <- x, 1., 0.;
    points.(point + 3) <- x, 0., 1.;
    for corner = 0 to 11 do
      triangles.((item * 12) + corner) <- point + local.(corner)
    done
  done;
  geometry points triangles

let pipeline ?axis_fast_path ?component_index left right =
  let constraints = Constraints.build ~grain:1 ~left ~right () |> get in
  let coplanar = Coplanar.build ~grain:1 constraints |> get in
  let refinement = Refinement.build ~coplanar ~grain:1 constraints |> get in
  let complex = Complex.build constraints refinement |> get in
  let radial = Radial.build complex |> get in
  let weiler = Weiler.build complex radial |> get in
  complex, weiler,
  Cells.build ?axis_fast_path ?component_index complex weiler |> get

let shell_values cells =
  let values = Array.init (Cells.shell_count cells) (fun shell ->
      Cells.left_winding cells shell, Cells.right_winding cells shell) in
  Array.sort Stdlib.compare values;
  values

let validate_relations complex weiler cells =
  for facet = 0 to Complex.facet_count complex - 1 do
    let negative = Weiler.half_facet_shell weiler
        (Weiler.half_facet facet Weiler.Negative)
    and positive = Weiler.half_facet_shell weiler
        (Weiler.half_facet facet Weiler.Positive) in
    check (Cells.left_winding cells positive
        = Cells.left_winding cells negative - Weiler.facet_left_winding weiler facet)
      "left winding propagation relation is broken";
    check (Cells.right_winding cells positive
        = Cells.right_winding cells negative - Weiler.facet_right_winding weiler facet)
      "right winding propagation relation is broken"
  done

let test_disjoint_solids () =
  let complex, weiler, cells = pipeline
      (tetra ~origin:(0.,0.,0.) 1.)
      (tetra ~origin:(10.,0.,0.) 1.) in
  check (shell_values cells = [|0,0; 0,0; 0,1; 1,0|])
    "disjoint solid winding cells are wrong";
  validate_relations complex weiler cells

let test_nested_solids () =
  let complex, weiler, cells = pipeline
      (tetra ~origin:(0.,0.,0.) 4.)
      (tetra ~origin:(1.,1.,1.) 0.5) in
  check (shell_values cells = [|0,0; 1,0; 1,0; 1,1|])
    "nested solid winding cells are wrong";
  validate_relations complex weiler cells

let signature complex weiler cells =
  shell_values cells,
  Array.init (Complex.facet_count complex) (fun facet ->
      Weiler.facet_left_winding weiler facet,
      Weiler.facet_right_winding weiler facet)

let test_domain_exactness () =
  let left = tetra ~origin:(0.,0.,0.) 4.
  and right = tetra ~origin:(1.,1.,1.) 0.5 in
  let run domains = Prismel.Parallel.run ~domains (fun () ->
      let complex, weiler, cells = pipeline left right in
      signature complex weiler cells) in
  if run 1 <> run 4 then fail "cell classification differs between domain counts"

let test_symbolic_seed_fallback () =
  let left = tetra ~origin:(0.,0.,0.) 4.
  and right = tetra ~origin:(1.,1.,1.) 0.5 in
  let run domains axis_fast_path = Prismel.Parallel.run ~domains (fun () ->
      let complex, weiler, cells = pipeline ~axis_fast_path left right in
      Cells.symbolic_seed_count cells, signature complex weiler cells) in
  let ordinary = run 1 true
  and symbolic_one = run 1 false
  and symbolic_four = run 4 false in
  check (fst symbolic_one > 0)
    "forced symbolic classification did not report its seed path";
  check (snd ordinary = snd symbolic_one)
    "axis and positive-infinitesimal cell classifications differ";
  check (symbolic_one = symbolic_four)
    "positive-infinitesimal cell classification differs between domain counts"

let test_component_index_exactness () =
  let fixtures = [|
    tetra ~origin:(0.,0.,0.) 1., tetra ~origin:(10.,0.,0.) 1.;
    tetra ~origin:(0.,0.,0.) 4., tetra ~origin:(1.,1.,1.) 0.5;
    tetra ~origin:(-2.,-2.,-2.) 4., tetra ~origin:(-1.,-1.,-1.) 4.;
  |] in
  Array.iteri (fun fixture (left, right) ->
      let run domains component_index axis_fast_path =
        Prismel.Parallel.run ~domains (fun () ->
            let complex, weiler, cells =
              pipeline ~component_index ~axis_fast_path left right in
            signature complex weiler cells) in
      let exhaustive = run 1 false true
      and indexed = run 1 true true
      and indexed_symbolic = run 1 true false
      and indexed_four = run 4 true true in
      if indexed <> exhaustive then
        fail "component index differs from exhaustive oracle for fixture %d" fixture;
      if indexed_symbolic <> exhaustive then
        fail "symbolic component index differs from exhaustive oracle for fixture %d"
          fixture;
      if indexed_four <> exhaustive then
        fail "component index differs between domain counts for fixture %d" fixture)
    fixtures

let test_component_index_scale () =
  let left = tetra_batch 64 0. and right = tetra_batch 64 3. in
  let run domains component_index = Prismel.Parallel.run ~domains (fun () ->
      let complex, weiler, cells = pipeline ~component_index left right in
      signature complex weiler cells) in
  let exhaustive = run 1 false and indexed = run 1 true
  and indexed_four = run 4 true in
  check (indexed = exhaustive)
    "component index scale result differs from exhaustive oracle";
  check (indexed_four = exhaustive)
    "component index scale result differs between domain counts"

let test_cancellation () =
  let complex, weiler, _ = pipeline
      (tetra ~origin:(0.,0.,0.) 1.)
      (tetra ~origin:(10.,0.,0.) 1.) in
  let cancel = Cancel.create () in Cancel.cancel cancel;
  match Cells.build ~cancel complex weiler with
  | Error error when Error.code error = "cancelled" -> ()
  | Error error -> fail "unexpected cancellation error: %s" (Error.to_string error)
  | Ok _ -> fail "cancelled cell classification completed"

let () =
  test_disjoint_solids ();
  test_nested_solids ();
  test_domain_exactness ();
  test_symbolic_seed_fallback ();
  test_component_index_exactness ();
  test_component_index_scale ();
  test_cancellation ()
