open Prismel
open Pdk

let fail message = failwith message
let get_ok = function Ok value -> value | Error error ->
  fail (Error.to_string error)
let get_string_ok = function Ok value -> value | Error message -> fail message
let near ?(epsilon = 1e-11) left right = abs_float (left -. right) <= epsilon

let add attribute geometry = Geometry.with_attribute attribute geometry |> get_string_ok
let add_group group geometry = Geometry.with_group group geometry |> get_string_ok

let float_attribute ~owner name values =
  Attribute.create_owned ~name ~owner (Attribute.Float values) |> get_string_ok

let text_attribute ~owner name values =
  Attribute.create_owned ~name ~owner (Attribute.Text values) |> get_string_ok

let float2_attribute ~owner name x y =
  let values = Packed.Float2.of_owned ~x ~y |> get_string_ok in
  Attribute.create_owned ~name ~owner (Attribute.Float2 values) |> get_string_ok

let float4_attribute ~owner name x y z w =
  let values = Packed.Float4.of_owned ~x ~y ~z ~w |> get_string_ok in
  Attribute.create_owned ~name ~owner (Attribute.Float4 values) |> get_string_ok

let attribute geometry owner name =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute -> attribute
  | None -> fail ("missing attribute " ^ name)

let point_float geometry name = match Attribute.Private.storage
    (attribute geometry Attribute.Point name) with
  | Attribute.Float values -> values
  | _ -> fail (name ^ " is not point float")

let point_int geometry name = match Attribute.Private.storage
    (attribute geometry Attribute.Point name) with
  | Attribute.Int values -> values
  | _ -> fail (name ^ " is not point int")

let point_text geometry name = match Attribute.Private.storage
    (attribute geometry Attribute.Point name) with
  | Attribute.Text values -> values
  | _ -> fail (name ^ " is not point text")

let point_float2 geometry name = match Attribute.Private.storage
    (attribute geometry Attribute.Point name) with
  | Attribute.Float2 values -> Packed.Float2.Private.view values
  | _ -> fail (name ^ " is not point float2")

let point_float3 geometry name = match Attribute.Private.storage
    (attribute geometry Attribute.Point name) with
  | Attribute.Float3 values -> Packed.Float3.Private.view values
  | _ -> fail (name ^ " is not point float3")

let point_float4 geometry name = match Attribute.Private.storage
    (attribute geometry Attribute.Point name) with
  | Attribute.Float4 values -> Packed.Float4.Private.view values
  | _ -> fail (name ^ " is not point float4")

let point_int_array geometry name = match Attribute.Private.storage
    (attribute geometry Attribute.Point name) with
  | Attribute.Int_array values -> Packed.Int_array.Private.view values
  | _ -> fail (name ^ " is not point int array")

let point_float_array geometry name = match Attribute.Private.storage
    (attribute geometry Attribute.Point name) with
  | Attribute.Float_array values -> Packed.Float_array.Private.view values
  | _ -> fail (name ^ " is not point float array")

let expect_code code = function
  | Error error when String.equal (Error.code error) code -> ()
  | Error error -> fail (Printf.sprintf "expected %s, received %s" code
      (Error.to_string error))
  | Ok _ -> fail ("expected " ^ code)

let two_triangles () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.; 0.; 10.; 11.; 10.|]
      ~y:[|0.; 0.; 0.; 0.; 0.; 0.|]
      ~z:[|0.; 0.; 1.; 0.; 0.; 1.|] in
  let topology = Topology.Builder.create ~point_count:6
      ~vertex_capacity:6 ~primitive_capacity:2 () in
  Topology.Builder.add_triangle topology 0 1 2;
  Topology.Builder.add_triangle topology 3 4 5;
  Geometry.create ~positions ~topology:(Topology.Builder.freeze topology) ()
  |> get_string_ok

let source_with_payload () =
  let source = two_triangles () in
  let point_x = Packed.Float3.Private.view (Geometry.positions source) in
  source
  |> add (float_attribute ~owner:Attribute.Primitive "density" [|0.; 2.|])
  |> add (float_attribute ~owner:Attribute.Point "foo" (Array.copy point_x.x))
  |> add (float2_attribute ~owner:Attribute.Vertex "corner"
       [|0.;1.;2.;3.;4.;5.|] [|10.;11.;12.;13.;14.;15.|])
  |> add (text_attribute ~owner:Attribute.Primitive "material" [|"left";"right"|])
  |> add (float4_attribute ~owner:Attribute.Detail "meta"
       [|7.|] [|8.|] [|9.|] [|10.|])
  |> add_group (Group.init ~owner:Group.Point ~name:"point_mark" 6
       (fun point -> point >= 3))
  |> add_group (Group.init ~owner:Group.Vertex ~name:"vertex_mark" 6
       (fun vertex -> vertex >= 3))
  |> add_group (Group.init ~owner:Group.Primitive ~name:"primitive_mark" 2
       (fun primitive -> primitive = 1))

let check_payload_and_provenance () =
  let source = source_with_payload () in
  let output = Ops.scatter_surface ~grain:37 ~count:4_000 ~seed:73
      ~density:(Ops.scatter_density ~owner:Attribute.Primitive "density")
      ~point_pattern:"foo point_mark" ~vertex_pattern:"corner vertex_mark"
      ~primitive_pattern:"material primitive_mark" ~detail_pattern:"meta"
      ~match_groups:true ~source_primitive_attribute:"source_primitive"
      ~source_vertex_numbers_attribute:"source_vertices"
      ~source_vertex_weights_attribute:"source_weights" source |> get_ok in
  if Geometry.point_count output <> 4_000 then fail "scatter cardinality";
  let positions = Packed.Float3.Private.view (Geometry.positions output)
  and normals = point_float3 output "N" and ids = point_int output "id"
  and primitives = point_int output "source_primitive"
  and numbers = point_int_array output "source_vertices"
  and weights = point_float_array output "source_weights"
  and foo = point_float output "foo" and corner = point_float2 output "corner"
  and material = point_text output "material" and meta = point_float4 output "meta" in
  if numbers.offsets <> weights.offsets
      || Array.length numbers.offsets <> 4_001
      || Array.length numbers.values <> 12_000 then
    fail "scatter provenance layout";
  for point = 0 to 3_999 do
    if ids.(point) <> point || primitives.(point) <> 1
        || positions.x.(point) < 10. || positions.x.(point) > 11.
        || positions.z.(point) < 0. || positions.z.(point) > 1.
        || not (near normals.x.(point) 0. && near (abs_float normals.y.(point)) 1.
          && near normals.z.(point) 0.)
        || not (near foo.(point) positions.x.(point))
        || not (String.equal material.(point) "right")
        || not (near meta.x.(point) 7. && near meta.y.(point) 8.
          && near meta.z.(point) 9. && near meta.w.(point) 10.) then
      fail "scatter payload values";
    let first = numbers.offsets.(point) in
    if numbers.values.(first) <> 3 || numbers.values.(first + 1) <> 4
        || numbers.values.(first + 2) <> 5 then
      fail "scatter source vertex numbers";
    let wa = weights.values.(first) and wb = weights.values.(first + 1)
    and wc = weights.values.(first + 2) in
    if not (near (wa +. wb +. wc) 1.
        && near positions.x.(point) (10. +. wb)
        && near positions.z.(point) wc
        && near corner.x.(point) ((3. *. wa) +. (4. *. wb) +. (5. *. wc))
        && near corner.y.(point) ((13. *. wa) +. (14. *. wb) +. (15. *. wc))) then
      fail "scatter barycentric reconstruction"
  done;
  List.iter (fun name -> match Geometry.find_group ~owner:Group.Point name output with
    | Some group when Group.cardinality group = 4_000 -> ()
    | _ -> fail ("scatter group interpolation " ^ name))
    ["point_mark"; "vertex_mark"; "primitive_mark"]

let check_selection_and_density () =
  let source = two_triangles () in
  let first = Group.init ~owner:Group.Primitive ~name:"first" 2
      (fun primitive -> primitive = 0) in
  let selected = Ops.scatter_surface ~primitives:first ~count:2_000 ~seed:9 source
      |> get_ok |> Geometry.positions |> Packed.Float3.Private.view in
  if Array.exists (fun x -> x < 0. || x > 1.) selected.x then
    fail "scatter primitive restriction";
  let negative = source
      |> add (float_attribute ~owner:Attribute.Primitive "density" [|-4.; 1.|]) in
  let weighted = Ops.scatter_surface ~count:2_000 ~seed:10
      ~density:(Ops.scatter_density ~owner:Attribute.Primitive "density") negative
      |> get_ok |> Geometry.positions |> Packed.Float3.Private.view in
  if Array.exists (fun x -> x < 10.) weighted.x then
    fail "negative density was not clamped to zero";
  let vertex_weighted = source
      |> add (float_attribute ~owner:Attribute.Vertex "vertex_density"
           [|0.;0.;0.;1.;1.;1.|])
      |> Ops.scatter_surface ~count:2_000 ~seed:12
           ~density:(Ops.scatter_density ~owner:Attribute.Vertex
             "vertex_density") |> get_ok |> Geometry.positions
      |> Packed.Float3.Private.view in
  if Array.exists (fun x -> x < 10.) vertex_weighted.x then
    fail "vertex density ownership";
  let detail_weighted = source
      |> add (float_attribute ~owner:Attribute.Detail "detail_density" [|2.|])
      |> Ops.scatter_surface ~count:17 ~seed:13
           ~density:(Ops.scatter_density ~owner:Attribute.Detail
             "detail_density") |> get_ok in
  if Geometry.point_count detail_weighted <> 17 then fail "detail density ownership";
  let one_triangle = Geometry.create
      ~positions:(Packed.Float3.Private.of_owned_exn
        ~x:[|0.;1.;0.|] ~y:[|0.;0.;0.|] ~z:[|0.;0.;1.|])
      ~topology:(Topology.polygons_owned ~point_count:3
        ~vertex_points:[|0;1;2|] ~primitive_offsets:[|0;3|] |> get_string_ok) ()
      |> get_string_ok
      |> add (float_attribute ~owner:Attribute.Point "density" [|1.;0.;0.|]) in
  let biased = Ops.scatter_surface ~count:50_000 ~seed:11
      ~density:(Ops.scatter_density ~owner:Attribute.Point "density") one_triangle
      |> get_ok |> Geometry.positions |> Packed.Float3.Private.view in
  let mean_x = Array.fold_left ( +. ) 0. biased.x /. 50_000.
  and mean_z = Array.fold_left ( +. ) 0. biased.z /. 50_000. in
  if abs_float (mean_x -. 0.25) > 0.012
      || abs_float (mean_z -. 0.25) > 0.012 then
    fail "linear point density sampling is biased incorrectly";
  let source_id = source
      |> add (Attribute.create_owned ~name:"id" ~owner:Attribute.Point
           (Attribute.Int (Array.make 6 99)) |> get_string_ok) in
  let generated_ids = Ops.scatter_surface ~count:40 ~seed:16
      ~point_pattern:"id" source_id |> get_ok |> fun geometry ->
      point_int geometry "id" in
  if generated_ids <> Array.init 40 Fun.id then
    fail "interpolated source id replaced generated scatter identity";
  let curve = Ops.polyline [|(100.,0.,0.);(101.,0.,0.);(102.,0.,0.)|]
      |> get_ok in
  let mixed = Ops.merge [source; curve] |> get_ok
      |> Ops.scatter_surface ~count:2_000 ~seed:14 |> get_ok
      |> Geometry.positions |> Packed.Float3.Private.view in
  if Array.exists (fun x -> x > 11.) mixed.x then
    fail "curve primitive contributed to surface scatter"

let check_ngon_provenance () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;2.;2.;1.;0.|] ~y:[|0.;0.;0.;0.;0.|]
      ~z:[|0.;0.;2.;1.;2.|] in
  let topology = Topology.Builder.create ~point_count:5 () in
  Topology.Builder.add_polygon topology [|0;1;2;3;4|];
  let source = Geometry.create ~positions ~topology:(Topology.Builder.freeze topology) ()
      |> get_string_ok in
  let output = Ops.scatter_surface ~count:5_000 ~seed:99
      ~source_vertex_numbers_attribute:"vertices"
      ~source_vertex_weights_attribute:"weights" source |> get_ok in
  let output_positions = Packed.Float3.Private.view (Geometry.positions output)
  and numbers = point_int_array output "vertices"
  and weights = point_float_array output "weights"
  and source_positions = Packed.Float3.Private.view positions in
  for point = 0 to 4_999 do
    let first = numbers.offsets.(point) in
    let x = ref 0. and y = ref 0. and z = ref 0. and sum = ref 0. in
    for slot = first to first + 2 do
      let source = Topology.point_of_vertex (Geometry.topology source)
          numbers.values.(slot) in
      let weight = weights.values.(slot) in
      sum := !sum +. weight;
      x := !x +. weight *. source_positions.x.(source);
      y := !y +. weight *. source_positions.y.(source);
      z := !z +. weight *. source_positions.z.(source)
    done;
    if not (near !sum 1. && near !x output_positions.x.(point)
        && near !y output_positions.y.(point)
        && near !z output_positions.z.(point)) then
      fail "concave N-gon provenance reconstruction"
  done

let check_errors () =
  let source = two_triangles () in
  expect_code "invalid_geometry" (Ops.scatter_surface ~count:(-1) ~seed:0 source);
  expect_code "invalid_geometry" (Ops.scatter_surface ~grain:0 ~count:1 ~seed:0 source);
  expect_code "invalid_geometry" (Ops.scatter_surface ~count:1 ~seed:0
    ~density:(Ops.scatter_density ~owner:Attribute.Point "missing") source);
  let wrong_density = source
      |> add (text_attribute ~owner:Attribute.Point "density"
           (Array.make 6 "bad")) in
  expect_code "invalid_geometry" (Ops.scatter_surface ~count:1 ~seed:0
    ~density:(Ops.scatter_density ~owner:Attribute.Point "density") wrong_density);
  let nan_density = source
      |> add (float_attribute ~owner:Attribute.Point "density"
           [|1.;1.;Float.nan;1.;1.;1.|]) in
  expect_code "invalid_geometry" (Ops.scatter_surface ~count:1 ~seed:0
    ~density:(Ops.scatter_density ~owner:Attribute.Point "density") nan_density);
  let zero_density = source
      |> add (float_attribute ~owner:Attribute.Detail "density" [|0.|]) in
  expect_code "invalid_geometry" (Ops.scatter_surface ~count:1 ~seed:0
    ~density:(Ops.scatter_density ~owner:Attribute.Detail "density") zero_density);
  let wrong_owner = Group.init ~owner:Group.Point ~name:"wrong" 6 (fun _ -> true) in
  expect_code "invalid_geometry" (Ops.scatter_surface ~primitives:wrong_owner
    ~count:1 ~seed:0 source);
  let wrong_length = Group.init ~owner:Group.Primitive ~name:"wrong" 1
      (fun _ -> true) in
  expect_code "invalid_geometry" (Ops.scatter_surface ~primitives:wrong_length
    ~count:1 ~seed:0 source);
  expect_code "invalid_geometry" (Ops.scatter_surface ~count:1 ~seed:0
    ~source_vertex_numbers_attribute:"numbers" source);
  expect_code "invalid_geometry" (Ops.scatter_surface ~count:1 ~seed:0
    ~source_primitive_attribute:"same"
    ~source_vertex_numbers_attribute:"same"
    ~source_vertex_weights_attribute:"weights" source);
  expect_code "invalid_geometry" (Ops.scatter_surface ~count:1 ~seed:0
    ~match_groups:true source);
  let curve = Ops.polyline [|(0.,0.,0.);(1.,0.,0.);(2.,0.,0.)|] |> get_ok in
  expect_code "invalid_geometry" (Ops.scatter_surface ~count:1 ~seed:0 curve);
  if Geometry.point_count (Ops.scatter_surface ~count:0 ~seed:0 curve |> get_ok) <> 0
  then fail "zero scatter on curve";
  let bad_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;0.;Float.nan;11.;10.|]
      ~y:[|0.;0.;0.;0.;0.;0.|] ~z:[|0.;0.;1.;0.;0.;1.|] in
  let bad_source = Geometry.create ~positions:bad_positions
      ~topology:(Geometry.topology source) () |> get_string_ok in
  expect_code "invalid_geometry"
    (Ops.scatter_surface ~count:1 ~seed:0 bad_source);
  let only_valid = Group.init ~owner:Group.Primitive ~name:"valid" 2
      (fun primitive -> primitive = 0) in
  if Geometry.point_count (Ops.scatter_surface ~primitives:only_valid
      ~count:20 ~seed:0 bad_source |> get_ok) <> 20 then
    fail "unselected non-finite primitive affected scatter";
  let extreme = Geometry.create
      ~positions:(Packed.Float3.Private.of_owned_exn
        ~x:[|-.max_float; max_float; 0.|]
        ~y:[|0.;0.;0.|] ~z:[|0.;0.;max_float|])
      ~topology:(Topology.polygons_owned ~point_count:3
        ~vertex_points:[|0;1;2|] ~primitive_offsets:[|0;3|] |> get_string_ok) ()
      |> get_string_ok in
  let extreme_positions = Ops.scatter_surface ~count:100 ~seed:15 extreme
      |> get_ok |> Geometry.positions |> Packed.Float3.Private.view in
  if not (Array.for_all Float.is_finite extreme_positions.x
      && Array.for_all Float.is_finite extreme_positions.y
      && Array.for_all Float.is_finite extreme_positions.z) then
    fail "extreme finite surface scatter overflow";
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  expect_code "cancelled" (Ops.scatter_surface ~cancel:cancelled ~count:100
    ~seed:0 source)

let check_parallel_scale () =
  let source = Ops.grid ~columns:300 ~rows:200 ~size:20. () |> get_ok in
  let count = Geometry.point_count source in
  let density = float_attribute ~owner:Attribute.Point "density"
      (Array.init count (fun point -> 0.1 +. float_of_int (point mod 97) /. 97.)) in
  let source = add density source in
  let scatter domains = Parallel.run ~domains (fun () ->
    Ops.scatter_surface ~grain:1_009 ~count:100_000 ~seed:1_337
      ~density:(Ops.scatter_density ~owner:Attribute.Point "density")
      ~point_pattern:"N" ~source_primitive_attribute:"primitive"
      ~source_vertex_numbers_attribute:"vertices"
      ~source_vertex_weights_attribute:"weights" source |> get_ok) in
  let one = scatter 1 and many = scatter 4 in
  let one_positions = Packed.Float3.Private.view (Geometry.positions one)
  and many_positions = Packed.Float3.Private.view (Geometry.positions many) in
  if one_positions.x <> many_positions.x || one_positions.y <> many_positions.y
      || one_positions.z <> many_positions.z
      || point_int one "id" <> point_int many "id"
      || point_int one "primitive" <> point_int many "primitive"
      || (point_int_array one "vertices").values
         <> (point_int_array many "vertices").values
      || (point_float_array one "weights").values
         <> (point_float_array many "weights").values
      || (point_float3 one "N").x <> (point_float3 many "N").x then
    fail "Scatter differs between one and four domains"

let () =
  check_payload_and_provenance ();
  check_selection_and_density ();
  check_ngon_provenance ();
  check_errors ();
  check_parallel_scale ();
  print_endline "scatter tests passed"
