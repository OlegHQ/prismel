open Prismel
open Pdk

let fail message = prerr_endline ("test_extract_centroid: " ^ message); exit 1
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error error -> fail (Error.to_string error)
let near a b = abs_float (a -. b) <= 1e-12

let positions geometry = Packed.Float3.Private.view (Geometry.positions geometry)

let attribute owner name storage =
  Attribute.create_owned ~owner ~name storage |> Result.get_ok

let with_attribute attribute geometry =
  Geometry.with_attribute attribute geometry |> Result.get_ok

let check_point geometry point (x, y, z) message =
  let p = positions geometry in
  check (near p.x.(point) x && near p.y.(point) y && near p.z.(point) z) message

let test_detail_methods () =
  let source = Ops.points [|0.,0.,0.; 2.,0.,0.; 10.,0.,0.|]
      |> with_attribute (attribute Attribute.Detail "author"
          (Attribute.Text [|"centroid"|])) in
  let mass = Ops.extract_centroid source |> get
  and bounds = Ops.extract_centroid ~method_:Ops.Centroid_bounding_box source |> get
  and hull = Ops.extract_centroid ~method_:Ops.Centroid_convex_hull source |> get in
  check (Geometry.point_count mass = 1 && Geometry.vertex_count mass = 0)
    "detail output cardinality";
  check_point mass 0 (4.,0.,0.) "point-mass center";
  check_point bounds 0 (5.,0.,0.) "bounds center";
  check_point hull 0 (5.,0.,0.) "linear hull center";
  check (Geometry.find_attribute ~owner:Attribute.Detail "author" mass
      = Geometry.find_attribute ~owner:Attribute.Detail "author" source)
    "detail payload sharing"

let test_planar_and_solid_hull_centers () =
  let triangle = Ops.points [|0.,0.,0.;2.,0.,0.;0.,2.,0.;0.25,0.25,0.|] in
  let triangle = Ops.extract_centroid ~method_:Ops.Centroid_convex_hull triangle
      |> get in
  check_point triangle 0 (2. /. 3., 2. /. 3., 0.) "planar hull area center";
  let tetra = Ops.points [|0.,0.,0.;1.,0.,0.;0.,1.,0.;0.,0.,1.;0.1,0.1,0.1|] in
  let tetra = Ops.extract_centroid ~method_:Ops.Centroid_convex_hull tetra |> get in
  check_point tetra 0 (0.25,0.25,0.25) "solid hull volume center"

let two_triangles () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;2.;0.;10.;14.;10.|] ~y:[|0.;0.;2.;0.;0.;2.|]
      ~z:(Array.make 6 0.) in
  let topology = Topology.polygons_owned ~point_count:6
      ~vertex_points:[|0;1;2;3;4;5|] ~primitive_offsets:[|0;3;6|]
      |> Result.get_ok in
  Geometry.create ~positions ~topology () |> Result.get_ok

let int_values owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute -> (match Attribute.Private.storage attribute with
      | Attribute.Int values -> values | _ -> fail (name ^ " storage"))
  | None -> fail (name ^ " missing")

let text_values owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute -> (match Attribute.Private.storage attribute with
      | Attribute.Text values -> values | _ -> fail (name ^ " storage"))
  | None -> fail (name ^ " missing")

let test_primitive_and_piece_modes () =
  let source = two_triangles () in
  let primitives = Ops.extract_centroid ~run_over:Ops.Centroid_primitives
      ~source_primitive_attribute:"sourceprim" source |> get in
  check (Geometry.point_count primitives = 2) "primitive center count";
  check_point primitives 0 (2. /. 3., 2. /. 3., 0.) "first primitive center";
  check_point primitives 1 (34. /. 3., 2. /. 3., 0.) "second primitive center";
  check (int_values Attribute.Point "sourceprim" primitives = [|0;1|])
    "source primitive field";
  let point_pieces = source |> with_attribute
      (attribute Attribute.Point "island" (Attribute.Int [|7;7;7;9;9;9|])) in
  let point_pieces = Ops.extract_centroid
      ~run_over:(Ops.Centroid_pieces {
        owner=Ops.Centroid_piece_points; attribute="island"}) point_pieces |> get in
  check (Geometry.point_count point_pieces = 2
      && int_values Attribute.Point "island" point_pieces = [|7;9|])
    "point piece identity";
  check_point point_pieces 0 (2. /. 3.,2. /. 3.,0.) "point piece first";
  let primitive_pieces = source |> with_attribute
      (attribute Attribute.Primitive "name" (Attribute.Text [|"both";"both"|])) in
  let primitive_pieces = Ops.extract_centroid
      ~run_over:(Ops.Centroid_pieces {
        owner=Ops.Centroid_piece_primitives; attribute="name"})
      ~piece_output_attribute:"piece" primitive_pieces |> get in
  check (Geometry.point_count primitive_pieces = 1
      && text_values Attribute.Point "piece" primitive_pieces = [|"both"|])
    "primitive piece identity";
  check_point primitive_pieces 0 (6., 2. /. 3., 0.)
    "primitive piece unique-point center"

let expect code work message = match work () with
  | Error error -> check (Error.code error = code) message
  | Ok _ -> fail (message ^ ": unexpectedly accepted")

let test_validation_and_cancellation () =
  expect "invalid_geometry" (fun () -> Ops.extract_centroid (Ops.points [||]))
    "empty detail";
  expect "invalid_geometry" (fun () -> Ops.extract_centroid ~grain:0
      (Ops.points [|0.,0.,0.|])) "zero grain";
  let bad = Ops.points [|Float.nan,0.,0.|] in
  expect "invalid_geometry" (fun () -> Ops.extract_centroid bad) "nonfinite";
  let source = two_triangles () in
  expect "invalid_geometry" (fun () -> Ops.extract_centroid
      ~run_over:(Ops.Centroid_pieces {
        owner=Ops.Centroid_piece_primitives; attribute="missing"}) source)
    "missing piece field";
  let wrong = source |> with_attribute
      (attribute Attribute.Primitive "bad" (Attribute.Float [|0.;1.|])) in
  expect "invalid_geometry" (fun () -> Ops.extract_centroid
      ~run_over:(Ops.Centroid_pieces {
        owner=Ops.Centroid_piece_primitives; attribute="bad"}) wrong)
    "wrong piece storage";
  let cancel = Cancel.create () in Cancel.cancel cancel;
  expect "cancelled" (fun () -> Ops.extract_centroid ~cancel source)
    "cancellation"

let equal left right =
  let lp = positions left and rp = positions right in
  lp.x = rp.x && lp.y = rp.y && lp.z = rp.z
  && List.map (fun attribute -> Attribute.name attribute,
      Attribute.owner attribute, Attribute.storage attribute)
      (Geometry.attributes left)
     = List.map (fun attribute -> Attribute.name attribute,
         Attribute.owner attribute, Attribute.storage attribute)
         (Geometry.attributes right)

let test_parallel_exact () =
  let columns = 400 and rows = 300 in
  let source = Ops.grid ~connectivity:Ops.Grid_triangles ~columns ~rows
      ~size:100. () |> get in
  let piece = attribute Attribute.Primitive "piece"
      (Attribute.Int (Array.init (Geometry.primitive_count source)
        (fun primitive -> primitive / 2))) in
  let source = source |> with_attribute piece in
  let cook domains = Parallel.run ~domains (fun () ->
    Ops.extract_centroid ~grain:257
      ~run_over:(Ops.Centroid_pieces {
        owner=Ops.Centroid_piece_primitives; attribute="piece"})
      ~method_:Ops.Centroid_bounding_box source |> get) in
  let one = cook 1 and four = cook 4 in
  check (equal one four) "one/four-domain output differs";
  check (Geometry.point_count one = columns * rows)
    "scale output cardinality"

let () =
  test_detail_methods ();
  test_planar_and_solid_hull_centers ();
  test_primitive_and_piece_modes ();
  test_validation_and_cancellation ();
  test_parallel_exact ();
  print_endline "extract centroid tests passed"
