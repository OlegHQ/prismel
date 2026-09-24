open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function Ok value -> value | Error error -> fail (Error.to_string error)

let points count = Ops.points (Array.init count (fun point ->
    float_of_int point, 0., 0.))

let with_attribute owner name storage geometry =
  let attribute = Attribute.create_owned ~owner ~name storage |> Result.get_ok in
  Geometry.with_attribute attribute geometry |> Result.get_ok

let with_float name values geometry =
  with_attribute Attribute.Point name (Attribute.Float values) geometry

let with_int name values geometry =
  with_attribute Attribute.Point name (Attribute.Int values) geometry

let float_values name geometry =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float values -> values
       | _ -> fail (name ^ " is not scalar float"))
  | None -> fail ("missing " ^ name)

let color_values geometry =
  match Geometry.find_attribute ~owner:Attribute.Point "Cd" geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float4 values -> Packed.Float4.Private.view values
       | _ -> fail "Cd is not float4")
  | None -> fail "missing Cd"

let check_floats expected actual message =
  check (Array.length expected = Array.length actual) (message ^ " length");
  Array.iteri (fun index expected ->
    if expected <> actual.(index) then fail (Printf.sprintf
      "%s at %d: expected %.17g, got %.17g" message index expected actual.(index)))
    expected

let test_timing_boundaries () =
  let starts = [|11.;10.;9.;8.;6.;5.;4.;3.;2.|] in
  let source = points (Array.length starts)
      |> with_float "fade" (Array.make (Array.length starts) 2.)
      |> with_float "start" starts in
  let output = Ops.attribute_fade ~grain:1 ~frame:10. ~start_attribute:"start"
      ~fade_in:2. ~fade_hold:3. ~fade_out:2. source |> get_ok in
  check_floats [|0.;0.;1.;2.;2.;2.;1.;0.;0.|]
    (float_values "fade" output) "Attribute Fade timing boundaries";
  let custom_endpoints = points 2
      |> with_float "start" [|8.;3.|] in
  let custom_endpoints = Ops.attribute_fade ~grain:1 ~frame:10.
      ~start_attribute:"start" ~fade_in:2. ~fade_hold:3. ~fade_out:2.
      ~fade_in_ramp:[0., 0.; 1., 0.75]
      ~fade_out_ramp:[0., 1.; 1., 0.25] custom_endpoints |> get_ok in
  check_floats [|0.75;0.25|] (float_values "fade" custom_endpoints)
    "Attribute Fade custom-ramp inclusive endpoints";
  let source_identity = points 4 |> with_float "fade" [|1.;1.;1.;1.|] in
  let identity = Ops.attribute_fade ~grain:1 ~frame:1. ~fade_in:0.
      ~fade_hold:10. ~fade_out:0. source_identity |> get_ok in
  check (identity == source_identity) "unchanged Attribute Fade lost identity"

let test_selection_ramps_and_visualization () =
  let source = points 5 in
  let selected = Group.init ~owner:Group.Point ~name:"selected" 5
      (fun point -> point = 1 || point = 2 || point = 3) in
  let output = Ops.attribute_fade ~grain:1 ~points:selected ~frame:1.
      ~fade_in:2. ~fade_hold:0. ~fade_out:0.
      ~fade_in_ramp:[0., 0.; 0.5, 0.25; 1., 1.] source |> get_ok in
  check_floats [|1.;0.25;0.25;0.25;1.|] (float_values "fade" output)
    "Attribute Fade selection/missing-field defaults";
  let colored_source = output |> with_attribute Attribute.Point "Cd"
      (Attribute.Float (Array.make 5 42.)) in
  let colored = Ops.attribute_fade ~grain:1 ~frame:1. ~fade_in:0.
      ~fade_hold:10. ~fade_out:0. ~visualize:true colored_source |> get_ok in
  let fade = float_values "fade" colored and color = color_values colored in
  for point = 0 to 4 do
    check (color.x.(point) = fade.(point) && color.y.(point) = fade.(point)
        && color.z.(point) = fade.(point) && color.w.(point) = 1.)
      "Attribute Fade visualization is not grayscale fade with opaque alpha"
  done

let test_reference_inputs_and_retime () =
  let target = points 4
      |> with_float "fade" [|1.;2.;3.;4.|]
      |> with_float "start" (Array.make 4 100.)
      |> with_float "hold" (Array.make 4 0.) in
  let start_source = points 4 |> with_int "start" [|1;2;3;4|]
  and hold_source = points 4 |> with_int "hold" [|2;1;3;0|] in
  let output = Ops.attribute_fade ~grain:1 ~start_source ~hold_source
      ~start_attribute:"start" ~start_retime:(1., 2.)
      ~hold_scale_attribute:"hold" ~frame:5. ~fade_in:1. ~fade_hold:3.
      ~fade_out:2. target |> get_ok in
  check_floats [|1.;0.;0.;0.|] (float_values "fade" output)
    "Attribute Fade independent reference/retime fields";
  let defaults = Ops.attribute_fade ~grain:1 ~start_source:(points 4)
      ~hold_source:(points 4) ~start_attribute:"missing_start"
      ~hold_scale_attribute:"missing_hold" ~frame:1. ~fade_in:0.
      ~fade_hold:2. ~fade_out:0. target |> get_ok in
  check_floats [|1.;2.;3.;4.|] (float_values "fade" defaults)
    "Attribute Fade missing reference defaults"

let expect_invalid work message = match work () with
  | Error error -> check (Error.code error = "invalid_attribute_fade") message
  | Ok _ -> fail (message ^ ": unexpectedly accepted")

let test_validation_and_cancellation () =
  let source = points 4 |> with_float "fade" [|1.;1.;1.;1.|] in
  List.iter (fun value -> expect_invalid (fun () ->
      Ops.attribute_fade ~frame:value source) "non-finite frame")
    [Float.nan; Float.infinity];
  List.iter (fun duration -> expect_invalid (fun () ->
      Ops.attribute_fade ~frame:0. ~fade_in:duration source)
      "invalid fade-in duration") [Float.nan; -1.];
  expect_invalid (fun () -> Ops.attribute_fade ~frame:0. ~grain:0 source)
    "zero grain";
  expect_invalid (fun () -> Ops.attribute_fade ~frame:0. ~fade_attribute:"P" source)
    "canonical P fade";
  expect_invalid (fun () -> Ops.attribute_fade ~frame:0. ~fade_attribute:"Cd"
      ~visualize:true source) "fade/Cd collision";
  expect_invalid (fun () -> Ops.attribute_fade ~frame:0.
      ~fade_in_ramp:[0., 0.; 0., 1.; 1., 1.] source) "duplicate ramp knot";
  expect_invalid (fun () -> Ops.attribute_fade ~frame:0.
      ~fade_out_ramp:[0.2, 1.; 1., 0.] source) "incomplete ramp";
  let wrong_fade = points 4 |> with_int "fade" [|1;1;1;1|] in
  expect_invalid (fun () -> Ops.attribute_fade ~frame:0. wrong_fade)
    "integer fade storage";
  let wrong_start = source |> with_attribute Attribute.Point "start"
      (Attribute.Text [|"0";"0";"0";"0"|]) in
  expect_invalid (fun () -> Ops.attribute_fade ~frame:0.
      ~start_attribute:"start" wrong_start) "text start storage";
  let wrong_hold = source |> with_attribute Attribute.Point "hold"
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:(Array.make 4 1.) ~y:(Array.make 4 1.) ~z:(Array.make 4 1.))) in
  expect_invalid (fun () -> Ops.attribute_fade ~frame:0.
      ~hold_scale_attribute:"hold" wrong_hold) "vector hold storage";
  let wrong_owner = Group.init ~owner:Group.Primitive ~name:"wrong" 0
      (fun _ -> false) in
  expect_invalid (fun () -> Ops.attribute_fade ~frame:0. ~points:wrong_owner source)
    "wrong selection owner";
  let wrong_length = Group.init ~owner:Group.Point ~name:"short" 3
      (fun _ -> true) in
  expect_invalid (fun () -> Ops.attribute_fade ~frame:0. ~points:wrong_length source)
    "wrong selection length";
  expect_invalid (fun () -> Ops.attribute_fade ~frame:0.
      ~start_source:(points 3) source) "reference cardinality";
  let negative_hold = source |> with_float "hold" [|1.;-1.;1.;1.|] in
  expect_invalid (fun () -> Ops.attribute_fade ~grain:1 ~frame:0.
      ~hold_scale_attribute:"hold" negative_hold) "negative hold scale";
  let overflow = points 1 |> with_float "fade" [|max_float|] in
  expect_invalid (fun () -> Ops.attribute_fade ~frame:1. ~fade_in:1.
      ~fade_in_ramp:[0., 0.; 1., 2.] overflow) "faded overflow";
  let elapsed_overflow = source |> with_float "start" [|-.max_float;0.;0.;0.|] in
  expect_invalid (fun () -> Ops.attribute_fade ~frame:max_float
      ~start_attribute:"start" elapsed_overflow) "relative-frame overflow";
  let malformed = source |> with_float "fade" [|1.;Float.nan;1.;Float.infinity|] in
  let error domains = Parallel.run ~domains (fun () ->
      Ops.attribute_fade ~grain:1 ~frame:0. malformed) in
  List.iter (fun domains -> match error domains with
    | Error error -> check (String.ends_with ~suffix:"point 1" (Error.message error))
        "Attribute Fade lowest malformed diagnostic is not deterministic"
    | Ok _ -> fail "Attribute Fade accepted non-finite selected fade") [1;4];
  let only_first = Group.init ~owner:Group.Point ~name:"first" 4
      (fun point -> point = 0) in
  let preserved = Ops.attribute_fade ~grain:1 ~points:only_first ~frame:0.
      malformed |> get_ok |> float_values "fade" in
  check (Float.is_nan preserved.(1) && preserved.(3) = Float.infinity)
    "Attribute Fade rejected or rewrote malformed unselected payload";
  let empty = Group.init ~owner:Group.Point ~name:"empty" 4 (fun _ -> false) in
  let unchanged = Ops.attribute_fade ~grain:1 ~points:empty ~frame:0. malformed
      |> get_ok in
  check (unchanged == malformed)
    "empty Attribute Fade selection lost identity on opaque payload";
  expect_invalid (fun () -> Ops.attribute_fade ~grain:1 ~points:only_first
      ~frame:0. ~visualize:true malformed) "visualized malformed payload";
  let cancel = Cancel.create () in
  Cancel.cancel cancel;
  (match Ops.attribute_fade ~cancel ~frame:0. source with
   | Error error -> check (Error.code error = "cancelled")
       "Attribute Fade cancellation code"
   | Ok _ -> fail "cancelled Attribute Fade published geometry")

let equal_float2 left right =
  let left = Packed.Float2.Private.view left and right = Packed.Float2.Private.view right in
  left.x = right.x && left.y = right.y

let equal_float3 left right =
  let left = Packed.Float3.Private.view left and right = Packed.Float3.Private.view right in
  left.x = right.x && left.y = right.y && left.z = right.z

let equal_float4 left right =
  let left = Packed.Float4.Private.view left and right = Packed.Float4.Private.view right in
  left.x = right.x && left.y = right.y && left.z = right.z && left.w = right.w

let equal_storage left right = match left, right with
  | Attribute.Float left, Attribute.Float right -> left = right
  | Attribute.Int left, Attribute.Int right -> left = right
  | Attribute.Float2 left, Attribute.Float2 right -> equal_float2 left right
  | Attribute.Float3 left, Attribute.Float3 right -> equal_float3 left right
  | Attribute.Float4 left, Attribute.Float4 right -> equal_float4 left right
  | Attribute.Text left, Attribute.Text right -> left = right
  | Attribute.Int_array left, Attribute.Int_array right ->
      let left = Packed.Int_array.Private.view left
      and right = Packed.Int_array.Private.view right in
      left.offsets = right.offsets && left.values = right.values
  | Attribute.Float_array left, Attribute.Float_array right ->
      let left = Packed.Float_array.Private.view left
      and right = Packed.Float_array.Private.view right in
      left.offsets = right.offsets && left.values = right.values
  | _ -> false

let equal_attributes left right =
  List.equal (fun left right -> Attribute.owner left = Attribute.owner right
      && String.equal (Attribute.name left) (Attribute.name right)
      && equal_storage (Attribute.Private.storage left)
           (Attribute.Private.storage right))
    (Geometry.attributes left) (Geometry.attributes right)

let test_dense_parallel_exactness () =
  let source = Ops.grid ~connectivity:Ops.Grid_quads ~columns:480 ~rows:300
      ~size:20. () |> get_ok in
  let point_count = Geometry.point_count source in
  let source = source
      |> with_float "fade" (Array.init point_count (fun point ->
           0.25 +. float_of_int (point mod 31) /. 32.))
      |> with_float "start" (Array.init point_count (fun point ->
           float_of_int (point mod 173) *. 0.75))
      |> with_int "hold" (Array.init point_count (fun point -> point mod 5)) in
  let selected = Group.init ~grain:257 ~owner:Group.Point ~name:"selected"
      point_count (fun point -> point mod 7 <> 0) in
  let cook domains = Parallel.run ~domains (fun () ->
      Ops.attribute_fade ~grain:257 ~points:selected ~frame:137.25
        ~start_attribute:"start" ~start_retime:(3., 0.75)
        ~hold_scale_attribute:"hold" ~fade_in:8. ~fade_hold:6. ~fade_out:16.
        ~fade_in_ramp:[0.,0.;0.3,0.08;0.72,0.9;1.,1.]
        ~fade_out_ramp:[0.,1.;0.25,0.96;0.65,0.18;1.,0.]
        ~visualize:true source |> get_ok) in
  let one = cook 1 and four = cook 4 in
  check (Geometry.positions one == Geometry.positions source
      && Geometry.topology one == Geometry.topology source)
    "Attribute Fade copied unchanged core planes";
  check (equal_attributes one four)
    "Attribute Fade one/four-domain attributes differ";
  let one_mesh = Prismel_mesh.to_mesh one |> get_ok
  and four_mesh = Prismel_mesh.to_mesh four |> get_ok in
  check (Mesh.Private.packed_view one_mesh = Mesh.Private.packed_view four_mesh)
    "Attribute Fade one/four-domain render mesh differs"

let () =
  test_timing_boundaries ();
  test_selection_ramps_and_visualization ();
  test_reference_inputs_and_retime ();
  test_validation_and_cancellation ();
  test_dense_parallel_exactness ();
  print_endline "pdk attribute fade tests passed"
