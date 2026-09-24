open Prismel
open Pdk

let fail message = prerr_endline ("test_extract_point_curve: " ^ message); exit 1
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error error -> fail (Error.to_string error)
let near a b = abs_float (a -. b) <= 1e-12

let attribute owner name storage =
  Attribute.create_owned ~owner ~name storage |> Result.get_ok

let with_attribute attribute geometry =
  Geometry.with_attribute attribute geometry |> Result.get_ok

let fixture () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;2.;3.;4.; 10.;11.;11.;10.|]
      ~y:[|0.;0.;0.;0.;0.; 0.;0.;1.;1.|] ~z:(Array.make 9 0.) in
  let topology = Topology.create_owned ~point_count:9
      ~vertex_points:[|0;1;2;3;4; 5;6;7;8|]
      ~primitive_offsets:[|0;5;9|]
      ~primitive_kinds:[|Topology.Open_polyline;Topology.Closed_polyline|]
      |> Result.get_ok in
  let rows = Packed.Float_array.create_owned
      ~offsets:[|0;1;2;3;4;5;6;7;8;9|]
      ~values:[|0.;10.;20.;30.;40.;50.;60.;70.;80.|] |> Result.get_ok in
  Geometry.create ~positions ~topology ~attributes:[
    attribute Attribute.Point "distance"
      (Attribute.Float [|-1.;0.;0.;1.;-1.; 0.;1.;-1.;0.|]);
    attribute Attribute.Point "weight"
      (Attribute.Float [|0.;10.;20.;30.;40.;50.;60.;70.;80.|]);
    attribute Attribute.Point "id" (Attribute.Int [|0;1;2;3;4;5;6;7;8|]);
    attribute Attribute.Point "label"
      (Attribute.Text [|"a";"b";"c";"d";"e";"f";"g";"h";"i"|]);
    attribute Attribute.Point "rows" (Attribute.Float_array rows);
    attribute Attribute.Primitive "cut" (Attribute.Float [|0.;0.5|]);
    attribute Attribute.Primitive "material" (Attribute.Int [|7;9|]);
    attribute Attribute.Detail "author" (Attribute.Text [|"curve"|]);
  ] () |> Result.get_ok

let positions geometry = Packed.Float3.Private.view (Geometry.positions geometry)

let float_values owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute -> (match Attribute.Private.storage attribute with
      | Attribute.Float values -> values | _ -> fail (name ^ " storage"))
  | None -> fail (name ^ " missing")

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

let test_constant_plateau_and_closed_seam () =
  let source = fixture () in
  let output = Ops.extract_point_from_curve ~distance_attribute:"distance"
      ~point_attributes:"weight id label rows" ~copy_primitive_attributes:true
      ~primitive_attributes:"material" ~curve_u_attribute:"curveu"
      ~number_cuts_attribute:"ncuts" ~curve_number_attribute:"curvenum"
      source |> get in
  check (Geometry.point_count output = 6 && Geometry.vertex_count output = 0)
    "constant extraction cardinality";
  let p = positions output in
  check (p.x = [|1.;2.;3.5;10.;11.;10.|]
      && p.y = [|0.;0.;0.;0.;0.5;1.|])
    "plateau/crossing/closed seam positions";
  check (float_values Attribute.Point "weight" output
      = [|10.;20.;35.;50.;65.;80.|]) "numeric interpolation";
  check (int_values Attribute.Point "id" output = [|1;2;4;5;7;8|])
    "nearest integer interpolation";
  check (text_values Attribute.Point "label" output
      = [|"b";"c";"e";"f";"h";"i"|]) "nearest text interpolation";
  check (int_values Attribute.Point "material" output = [|7;7;7;9;9;9|])
    "primitive attribute copy";
  check (float_values Attribute.Point "curveu" output
      = [|0.25;0.5;0.875;0.;0.375;0.75|]) "uniform-edge curve U";
  check (int_values Attribute.Point "ncuts" output = [|3;3;3;3;3;3|]
      && int_values Attribute.Point "curvenum" output = [|0;0;0;1;1;1|])
    "cut count and curve number";
  check (Geometry.find_attribute ~owner:Attribute.Detail "author" output
      = Geometry.find_attribute ~owner:Attribute.Detail "author" source)
    "detail structural sharing";
  let rows = match Geometry.find_attribute ~owner:Attribute.Point "rows" output with
    | Some attribute -> (match Attribute.Private.storage attribute with
        | Attribute.Float_array values -> values | _ -> fail "rows storage")
    | None -> fail "rows missing" in
  check (Packed.Float_array.get rows 2 = [|40.|]) "ragged nearest transfer"

let test_per_curve_target_and_selection () =
  let source = fixture () in
  let first = Group.init ~owner:Group.Primitive ~name:"first" 2
      (fun primitive -> primitive = 0) in
  let output = Ops.extract_point_from_curve ~primitives:first
      ~cut:(Ops.Extract_cut_primitive_attribute "cut")
      ~distance_attribute:"distance" ~curve_number_attribute:"curve" source |> get in
  check (Geometry.point_count output = 3
      && int_values Attribute.Point "curve" output = [|0;0;0|])
    "primitive restriction";
  let all = Ops.extract_point_from_curve
      ~cut:(Ops.Extract_cut_primitive_attribute "cut")
      ~distance_attribute:"distance" source |> get in
  check (Geometry.point_count all = 5) "varying target cardinality";
  let p = positions all in
  check (near p.x.(3) 10.5 && near p.y.(3) 0.
      && near p.x.(4) 11. && near p.y.(4) 0.25)
    "varying target positions"

let test_open_last_endpoint () =
  let source = Ops.polyline [|0.,0.,0.;1.,0.,0.;2.,0.,0.|] |> get
      |> with_attribute (attribute Attribute.Point "d"
          (Attribute.Float [|-1.;-1.;0.|])) in
  let output = Ops.extract_point_from_curve ~distance_attribute:"d" source |> get in
  check (Geometry.point_count output = 1 && (positions output).x = [|2.|])
    "open final endpoint"

let test_empty_selection_and_extreme_scale () =
  let source = fixture () in
  let empty = Group.init ~owner:Group.Primitive ~name:"empty" 2
      (fun _ -> false) in
  let output = Ops.extract_point_from_curve ~primitives:empty
      ~distance_attribute:"distance" source |> get in
  check (Geometry.point_count output = 0 && Geometry.vertex_count output = 0)
    "empty selection cardinality";
  check (Geometry.find_attribute ~owner:Attribute.Detail "author" output
      = Geometry.find_attribute ~owner:Attribute.Detail "author" source)
    "empty selection detail structural sharing";
  let extreme = Ops.polyline
      [|(-.Float.max_float),0.,0.; Float.max_float,0.,0.|] |> get
      |> with_attribute (attribute Attribute.Point "d"
          (Attribute.Float [|(-.Float.max_float);Float.max_float|])) in
  let midpoint = Ops.extract_point_from_curve ~distance_attribute:"d" extreme
      |> get in
  check (Geometry.point_count midpoint = 1
      && (positions midpoint).x = [|0.|])
    "scale-safe crossing interpolation"

let expect code work message = match work () with
  | Error error -> check (Error.code error = code) message
  | Ok _ -> fail (message ^ ": unexpectedly accepted")

let test_validation_and_cancellation () =
  let source = fixture () in
  expect "invalid_curve" (fun () -> Ops.extract_point_from_curve
      ~distance_attribute:"missing" source) "missing distance";
  expect "invalid_curve" (fun () -> Ops.extract_point_from_curve ~grain:0
      ~distance_attribute:"distance" source) "zero grain";
  expect "invalid_curve" (fun () -> Ops.extract_point_from_curve
      ~cut:(Ops.Extract_cut_constant Float.nan)
      ~distance_attribute:"distance" source) "nonfinite constant";
  expect "invalid_curve" (fun () -> Ops.extract_point_from_curve
      ~distance_attribute:"distance" ~point_attributes:"[" source)
    "malformed pattern";
  expect "invalid_curve" (fun () -> Ops.extract_point_from_curve
      ~distance_attribute:"distance" ~curve_u_attribute:"P" source)
    "invalid output name";
  expect "invalid_curve" (fun () -> Ops.extract_point_from_curve
      ~distance_attribute:"distance" ~curve_u_attribute:"u"
      ~curve_number_attribute:"u" source) "duplicate diagnostics";
  expect "invalid_curve" (fun () -> Ops.extract_point_from_curve
      ~distance_attribute:"distance" ~point_attributes:"id"
      ~copy_primitive_attributes:true ~primitive_attributes:"material"
      ~curve_number_attribute:"id" source) "attribute collision";
  let point_owned = Group.init ~owner:Group.Point ~name:"points" 9
      (fun _ -> true) in
  expect "invalid_curve" (fun () -> Ops.extract_point_from_curve
      ~primitives:point_owned ~distance_attribute:"distance" source)
    "wrong selection owner";
  let wrong_length = Group.init ~owner:Group.Primitive ~name:"short" 1
      (fun _ -> true) in
  expect "invalid_curve" (fun () -> Ops.extract_point_from_curve
      ~primitives:wrong_length ~distance_attribute:"distance" source)
    "wrong selection cardinality";
  let polygon = Ops.grid ~connectivity:Ops.Grid_quads ~columns:1 ~rows:1
      ~size:1. () |> get |> with_attribute
      (attribute Attribute.Point "distance" (Attribute.Float [|0.;1.;0.;1.|])) in
  expect "invalid_curve" (fun () -> Ops.extract_point_from_curve
      ~distance_attribute:"distance" polygon) "polygon input";
  let bad = source |> Geometry.with_attribute
      (attribute Attribute.Point "bad"
        (Attribute.Float [|0.;0.;0.;0.;Float.nan;0.;0.;0.;0.|]))
      |> Result.get_ok in
  expect "invalid_curve" (fun () -> Ops.extract_point_from_curve
      ~distance_attribute:"bad" bad) "nonfinite field";
  let bad_cut = source |> Geometry.with_attribute
      (attribute Attribute.Primitive "bad_cut"
        (Attribute.Float [|0.;Float.infinity|])) |> Result.get_ok in
  expect "invalid_curve" (fun () -> Ops.extract_point_from_curve
      ~cut:(Ops.Extract_cut_primitive_attribute "bad_cut")
      ~distance_attribute:"distance" bad_cut) "nonfinite primitive cut";
  let cancel = Cancel.create () in Cancel.cancel cancel;
  expect "cancelled" (fun () -> Ops.extract_point_from_curve ~cancel
      ~distance_attribute:"distance" source) "cancellation"

let equal_geometry left right =
  let lp = positions left and rp = positions right in
  lp.x = rp.x && lp.y = rp.y && lp.z = rp.z
  && List.map (fun attribute -> Attribute.name attribute,
      Attribute.owner attribute, Attribute.storage attribute)
      (Geometry.attributes left)
     = List.map (fun attribute -> Attribute.name attribute,
         Attribute.owner attribute, Attribute.storage attribute)
         (Geometry.attributes right)

let large_fixture count =
  let points = count * 2 in
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:(Array.init points (fun point -> Float.of_int (point / 2)))
      ~y:(Array.init points (fun point -> Float.of_int (point land 1)))
      ~z:(Array.make points 0.) in
  let topology = Topology.create_owned ~point_count:points
      ~vertex_points:(Array.init points Fun.id)
      ~primitive_offsets:(Array.init (count + 1) (fun primitive -> primitive * 2))
      ~primitive_kinds:(Array.make count Topology.Open_polyline) |> Result.get_ok in
  Geometry.create ~positions ~topology ~attributes:[
    attribute Attribute.Point "distance"
      (Attribute.Float (Array.init points (fun point -> if point land 1 = 0 then -1. else 1.)));
    attribute Attribute.Point "weight"
      (Attribute.Float (Array.init points Float.of_int));
    attribute Attribute.Primitive "material"
      (Attribute.Int (Array.init count (fun primitive -> primitive mod 17)))] ()
  |> Result.get_ok

let long_curve_fixture point_count =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:(Array.init point_count Float.of_int) ~y:(Array.make point_count 0.)
      ~z:(Array.make point_count 0.) in
  let topology = Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:[|0;point_count|]
      ~primitive_kinds:[|Topology.Open_polyline|] |> Result.get_ok in
  Geometry.create ~positions ~topology ~attributes:[
    attribute Attribute.Point "distance" (Attribute.Float
      (Array.init point_count (fun point -> if point land 1 = 0 then -1. else 1.)));
    attribute Attribute.Point "weight"
      (Attribute.Float (Array.init point_count Float.of_int))] ()
  |> Result.get_ok

let test_parallel_exact () =
  let source = large_fixture 100_000 in
  let cook domains = Parallel.run ~domains (fun () ->
    Ops.extract_point_from_curve ~grain:257 ~distance_attribute:"distance"
      ~point_attributes:"weight" ~copy_primitive_attributes:true
      ~primitive_attributes:"material" ~curve_u_attribute:"u"
      ~number_cuts_attribute:"n" ~curve_number_attribute:"curve" source |> get) in
  let one = cook 1 and four = cook 4 in
  check (equal_geometry one four) "one/four-domain geometry differs";
  check (Geometry.point_count one = 100_000) "scale output cardinality";
  let long_source = long_curve_fixture 200_001 in
  let cook_long domains = Parallel.run ~domains (fun () ->
    Ops.extract_point_from_curve ~grain:257 ~distance_attribute:"distance"
      ~point_attributes:"weight" ~curve_u_attribute:"u" long_source |> get) in
  let long_one = cook_long 1 and long_four = cook_long 4 in
  check (equal_geometry long_one long_four)
    "long-curve block one/four-domain geometry differs";
  check (Geometry.point_count long_one = 200_000)
    "long-curve block output cardinality"

let () =
  test_constant_plateau_and_closed_seam ();
  test_per_curve_target_and_selection ();
  test_open_last_endpoint ();
  test_empty_selection_and_extreme_scale ();
  test_validation_and_cancellation ();
  test_parallel_exact ();
  print_endline "extract point from curve tests passed"
