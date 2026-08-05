open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function Ok value -> value | Error error -> fail (Error.to_string error)
let get_string = function Ok value -> value | Error error -> fail error
let near ?(epsilon = 1e-9) left right = abs_float (left -. right) <= epsilon

let attribute geometry owner name =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute -> attribute
  | None -> fail ("missing attribute " ^ name)

let float_attribute geometry name =
  match Attribute.Private.storage (attribute geometry Attribute.Point name) with
  | Attribute.Float values -> values
  | _ -> fail (name ^ " has unexpected storage")

let int_attribute geometry name =
  match Attribute.Private.storage (attribute geometry Attribute.Point name) with
  | Attribute.Int values -> values
  | _ -> fail (name ^ " has unexpected storage")

let float3_attribute geometry name =
  match Attribute.Private.storage (attribute geometry Attribute.Point name) with
  | Attribute.Float3 values -> Packed.Float3.Private.view values
  | _ -> fail (name ^ " has unexpected storage")

let equal_storage left right =
  match Attribute.storage left, Attribute.storage right with
  | Attribute.Float left, Attribute.Float right -> left = right
  | Attribute.Int left, Attribute.Int right -> left = right
  | Attribute.Text left, Attribute.Text right -> left = right
  | Attribute.Float2 left, Attribute.Float2 right ->
      let left = Packed.Float2.Private.view left
      and right = Packed.Float2.Private.view right in
      left.x = right.x && left.y = right.y
  | Attribute.Float3 left, Attribute.Float3 right ->
      let left = Packed.Float3.Private.view left
      and right = Packed.Float3.Private.view right in
      left.x = right.x && left.y = right.y && left.z = right.z
  | Attribute.Float4 left, Attribute.Float4 right ->
      let left = Packed.Float4.Private.view left
      and right = Packed.Float4.Private.view right in
      left.x = right.x && left.y = right.y && left.z = right.z
      && left.w = right.w
  | Attribute.Int_array left, Attribute.Int_array right ->
      let left = Packed.Int_array.Private.view left
      and right = Packed.Int_array.Private.view right in
      left.offsets = right.offsets && left.values = right.values
  | Attribute.Float_array left, Attribute.Float_array right ->
      let left = Packed.Float_array.Private.view left
      and right = Packed.Float_array.Private.view right in
      left.offsets = right.offsets && left.values = right.values
  | _ -> false

let equal_group left right =
  Group.owner left = Group.owner right
  && String.equal (Group.name left) (Group.name right)
  && Group.length left = Group.length right
  && Group.ordered_elements left = Group.ordered_elements right
  && begin
    let equal = ref true in
    for element = 0 to Group.length left - 1 do
      if Group.mem element left <> Group.mem element right then equal := false
    done;
    !equal
  end

let equal_edge_group left right =
  String.equal (Edge_group.name left) (Edge_group.name right)
  && Edge_group.length left = Edge_group.length right
  && begin
    let equal = ref true in
    for edge = 0 to Edge_group.length left - 1 do
      if Edge_group.mem edge left <> Edge_group.mem edge right then equal := false
    done;
    !equal
  end

let equal_geometry left right =
  let lp = Packed.Float3.Private.view (Geometry.positions left)
  and rp = Packed.Float3.Private.view (Geometry.positions right)
  and lt = Topology.Private.view (Geometry.topology left)
  and rt = Topology.Private.view (Geometry.topology right) in
  lp.x = rp.x && lp.y = rp.y && lp.z = rp.z
  && lt.point_count = rt.point_count
  && lt.vertex_points = rt.vertex_points
  && lt.primitive_offsets = rt.primitive_offsets
  && Bytes.equal lt.primitive_kinds rt.primitive_kinds
  && List.equal (fun left right ->
       Attribute.owner left = Attribute.owner right
       && String.equal (Attribute.name left) (Attribute.name right)
       && String.equal (Attribute.kind_name left) (Attribute.kind_name right)
       && equal_storage left right)
       (Geometry.attributes left) (Geometry.attributes right)
  && List.equal equal_group (Geometry.groups left) (Geometry.groups right)
  && List.equal equal_edge_group
       (Geometry.edge_groups left) (Geometry.edge_groups right)

let expect_invalid = function
  | Error error when Error.code error = "invalid_geometry" -> ()
  | Error error -> fail ("unexpected error " ^ Error.to_string error)
  | Ok _ -> fail "expected invalid Resample input"

let x_positions geometry =
  (Packed.Float3.Private.view (Geometry.positions geometry)).x

let with_primitive_attribute name storage geometry =
  let attribute = Attribute.create_owned ~owner:Attribute.Primitive ~name storage
      |> get_string in
  Geometry.with_attribute attribute geometry |> get_string

let check_length_modes () =
  let line = Ops.polyline [|(0., 0., 0.); (2.5, 0., 0.)|] |> get_ok in
  let even = Ops.resample_curves ~maximum_segment_length:1. line |> get_ok in
  let x = x_positions even in
  check (Array.length x = 4 && near x.(0) 0. && near x.(1) (2.5 /. 3.)
      && near x.(2) (5. /. 3.) && near x.(3) 2.5)
    "equal-last maximum-length sampling";
  let short_last = Ops.resample_curves ~maximum_segment_length:1.
      ~even_last_segment:false line |> get_ok in
  let x = x_positions short_last in
  check (x = [|0.; 1.; 2.; 2.5|]) "short final segment sampling";
  let capped = Ops.resample_curves ~segments:2 ~maximum_segment_length:1.
      ~even_last_segment:false line |> get_ok in
  let x = x_positions capped in
  check (x = [|0.; 1.25; 2.5|]) "maximum-segment ceiling sampling";
  let square = Ops.polyline ~closed:true
      [|(0., 0., 0.); (1., 0., 0.); (1., 1., 0.); (0., 1., 0.)|]
      |> get_ok in
  let closed = Ops.resample_curves ~maximum_segment_length:10.
      ~even_last_segment:false square |> get_ok in
  check (Geometry.point_count closed = 3
      && Topology.primitive_kind (Geometry.topology closed) 0
         = Topology.Closed_polyline)
    "closed length mode minimum cardinality"

let check_diagnostics () =
  let bent = Ops.polyline [|(0., 0., 0.); (1., 0., 0.); (1., 3., 0.)|]
      |> get_ok in
  let result = Ops.resample_curves ~segments:4 ~curve_u_attribute:"curveu"
      ~curve_number_attribute:"curvenum" ~distance_attribute:"distance"
      ~tangent_attribute:"tangent" bent |> get_ok in
  let u = float_attribute result "curveu"
  and curve = int_attribute result "curvenum"
  and distance = float_attribute result "distance"
  and tangent = float3_attribute result "tangent" in
  check (Array.length u = 5 && near u.(0) 0. && near u.(1) 0.5
      && near u.(2) (2. /. 3.) && near u.(3) (5. /. 6.) && near u.(4) 1.)
    "polygon curve-U output";
  check (curve = [|0; 0; 0; 0; 0|]) "curve-number output";
  check (distance = [|0.5; 1.; 1.; 1.; 0.5|]) "coverage-distance output";
  let diagonal = 1. /. sqrt 2. in
  check (near tangent.x.(0) 1. && near tangent.y.(0) 0.
      && near tangent.x.(1) diagonal && near tangent.y.(1) diagonal
      && near tangent.x.(2) 0. && near tangent.y.(2) 1.)
    "output tangent field"

let check_group_and_overrides () =
  let first = Ops.polyline [|(0., 0., 0.); (2., 0., 0.)|] |> get_ok
  and second = Ops.polyline
      [|(10., 0., 0.); (11., 1., 0.); (12., 0., 0.)|] |> get_ok in
  let source = Ops.merge [first; second] |> get_ok in
  let selected = Group.init ~owner:Group.Primitive ~name:"first" 2
      (fun primitive -> primitive = 0) in
  let restricted = Ops.resample_curves ~primitives:selected ~segments:4 source
      |> get_ok in
  let topology = Geometry.topology restricted in
  let first_start, first_end = Topology.primitive_vertex_range topology 0
  and second_start, second_end = Topology.primitive_vertex_range topology 1 in
  check (first_end - first_start = 5 && second_end - second_start = 3)
    "primitive-group restriction did not preserve unselected curve";
  let positions = Packed.Float3.Private.view (Geometry.positions restricted) in
  check (positions.x.(second_start) = 10. && positions.x.(second_start + 1) = 11.
      && positions.x.(second_start + 2) = 12.)
    "unselected curve did not preserve exact source points";
  let overridden = source
      |> with_primitive_attribute "segment_length"
           (Attribute.Float [|0.; 0.|])
      |> with_primitive_attribute "num_segments" (Attribute.Int [|2; 0|]) in
  let run domains = Parallel.run ~domains (fun () ->
      Ops.resample_curves ~grain:1 ~segments:7 ~maximum_segment_length:0.2
        ~segment_length_attribute:"segment_length"
        ~segments_attribute:"num_segments" overridden |> get_ok) in
  let one = run 1 and many = run 4 in
  check (equal_geometry one many)
    "one-domain and four-domain override Resample geometry differ";
  let topology = Geometry.topology one in
  let a0, a1 = Topology.primitive_vertex_range topology 0
  and b0, b1 = Topology.primitive_vertex_range topology 1 in
  check (a1 - a0 = 3 && b1 - b0 = 3)
    "primitive override disable/preserve semantics"

let check_validation () =
  let line = Ops.polyline [|(0., 0., 0.); (1., 0., 0.)|] |> get_ok in
  expect_invalid (Ops.resample_curves line);
  expect_invalid (Ops.resample_curves ~segments:0 line);
  expect_invalid (Ops.resample_curves ~maximum_segment_length:0. line);
  expect_invalid (Ops.resample_curves ~maximum_segment_length:Float.nan line);
  expect_invalid (Ops.resample_curves ~segments:max_int line);
  expect_invalid (Ops.resample_curves ~segments:2 ~curve_u_attribute:" " line);
  expect_invalid (Ops.resample_curves ~segments:2 ~curve_u_attribute:"P" line);
  expect_invalid (Ops.resample_curves ~segments:2 ~curve_u_attribute:"u"
      ~distance_attribute:"u" line);
  expect_invalid (Ops.resample_curves ~segments:2
      ~segment_length_attribute:"missing" line);
  let wrong_override = line |> with_primitive_attribute "segment_length"
      (Attribute.Int [|1|]) in
  expect_invalid (Ops.resample_curves ~segments:2
      ~segment_length_attribute:"segment_length" wrong_override);
  let nonfinite_override = line |> with_primitive_attribute "segment_length"
      (Attribute.Float [|Float.infinity|]) in
  expect_invalid (Ops.resample_curves ~segments:2
      ~segment_length_attribute:"segment_length" nonfinite_override);
  let wrong_group = Group.init ~owner:Group.Point ~name:"points" 2
      (fun _ -> true) in
  expect_invalid (Ops.resample_curves ~primitives:wrong_group ~segments:2 line);
  let repeated = Ops.polyline [|(0., 0., 0.); (0., 0., 0.)|] |> get_ok in
  expect_invalid (Ops.resample_curves ~segments:2 repeated);
  let polygon = Ops.grid ~columns:1 ~rows:1 ~size:1. () |> get_ok in
  expect_invalid (Ops.resample_curves ~segments:2 polygon);
  let closed = Ops.polyline ~closed:true
      [|(0., 0., 0.); (1., 0., 0.); (0., 1., 0.)|] |> get_ok in
  expect_invalid (Ops.resample_curves ~segments:2 closed);
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.resample_curves ~cancel:cancelled ~segments:2 line with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "Resample ignored cancellation")

let check_parallel_exact () =
  let count = 5_001 in
  let source = Array.init count (fun point ->
      let t = float_of_int point *. 0.003 in
      t, sin (t *. 0.7), cos (t *. 0.43) *. 0.6) |> Ops.polyline |> get_ok
      |> Ops.group_edges ~grain:257 ~name:"spine_edges" |> get_ok in
  let run domains = Parallel.run ~domains (fun () ->
      Ops.resample_curves ~grain:257 ~maximum_segment_length:0.0009
        ~curve_u_attribute:"curveu" ~curve_number_attribute:"curvenum"
        ~distance_attribute:"distance" ~tangent_attribute:"tangent" source
      |> get_ok) in
  let one = run 1 and many = run 4 in
  check (equal_geometry one many)
    "one-domain and four-domain Resample geometry differ";
  check (Geometry.point_count one > count
      && Geometry.find_edge_group "spine_edges" one <> None)
    "parallel Resample cardinality/edge provenance"

let () =
  check_length_modes ();
  check_diagnostics ();
  check_group_and_overrides ();
  check_validation ();
  check_parallel_exact ();
  print_endline "Resample tests passed"
