open Prismel
open Pdk

let fail message = raise (Failure message)
let get_ok = function Ok value -> value | Error error -> fail (Error.to_string error)

let add storage ~owner ~name geometry =
  let attribute = Attribute.create_owned ~owner ~name storage |> Result.get_ok in
  Geometry.with_attribute attribute geometry |> Result.get_ok

let float_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float values -> values
       | _ -> fail ("wrong float storage for " ^ name))
  | None -> fail ("missing " ^ name)

let int_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Int values -> values
       | _ -> fail ("wrong int storage for " ^ name))
  | None -> fail ("missing " ^ name)

let float3_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float3 values -> Packed.Float3.Private.view values
       | _ -> fail ("wrong float3 storage for " ^ name))
  | None -> fail ("missing " ^ name)

let float4_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float4 values -> Packed.Float4.Private.view values
       | _ -> fail ("wrong float4 storage for " ^ name))
  | None -> fail ("missing " ^ name)

let combine ?selection ?match_attribute ?create_missing
    ?create_missing_as_scalar ?delete_sources ?error_on_missing ?overall_scale
    ?threshold ?minimum ?maximum ~owner ~destination ~layers geometries =
  Attribute_ops.combine ?selection ?match_attribute ?create_missing
    ?create_missing_as_scalar ?delete_sources ?error_on_missing ?overall_scale
    ?threshold ?minimum ?maximum ~owner ~destination ~layers ~geometries ()
  |> get_ok

let base_scalar () =
  Ops.points [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.)|]
  |> add (Attribute.Float [|4.;4.;4.|]) ~owner:Attribute.Point ~name:"dest"
  |> add (Attribute.Float [|2.;2.;0.|]) ~owner:Attribute.Point ~name:"src"

let test_operations () =
  let cases = [
    Attribute_ops.Combine_copy, [|2.;2.;0.|];
    Attribute_ops.Combine_add, [|6.;6.;4.|];
    Attribute_ops.Combine_subtract, [|2.;2.;4.|];
    Attribute_ops.Combine_multiply, [|8.;8.;0.|];
    Attribute_ops.Combine_divide, [|2.;2.;0.|];
    Attribute_ops.Combine_maximum, [|4.;4.;4.|];
    Attribute_ops.Combine_minimum, [|2.;2.;0.|];
  ] in
  List.iter (fun (operation, expected) ->
    let geometry = base_scalar () in
    let layer = Attribute_ops.combine_layer ~source:"src" operation in
    let result = combine ~owner:Attribute.Point ~destination:"dest"
        ~layers:[layer] [|geometry|] in
    if float_values ~owner:Attribute.Point "dest" result <> expected then
      fail "Attribute Combine arithmetic operation") cases

let test_processing_and_blend () =
  let geometry = Ops.points [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.)|]
      |> add (Attribute.Float [|0.;0.;0.|])
           ~owner:Attribute.Point ~name:"dest"
      |> add (Attribute.Float [|-1.;0.25;2.|])
           ~owner:Attribute.Point ~name:"src"
      |> add (Attribute.Float [|0.;0.5;3.|])
           ~owner:Attribute.Point ~name:"mask" in
  let layer = Attribute_ops.combine_layer ~source:"src" ~scale:2. ~add:0.5
      ~process:Attribute_ops.Combine_complement_clamp_01 ~blend:0.5
      ~blend_attribute:"mask" Attribute_ops.Combine_copy in
  let result = combine ~owner:Attribute.Point ~destination:"dest"
      ~layers:[layer] [|geometry|] in
  if float_values ~owner:Attribute.Point "dest" result <> [|0.;0.;0.|] then
    fail "Attribute Combine preprocessing/blend";
  let reciprocal = Attribute_ops.combine_layer ~source:"src"
      ~process:Attribute_ops.Combine_reciprocal Attribute_ops.Combine_copy in
  let result = combine ~owner:Attribute.Point ~destination:"dest"
      ~layers:[reciprocal] [|geometry|] in
  if float_values ~owner:Attribute.Point "dest" result
      <> [|1.;4.;0.5|] then fail "Attribute Combine reciprocal";
  let threshold = Attribute_ops.combine_layer ~source:"src"
      ~process:Attribute_ops.Combine_threshold_half Attribute_ops.Combine_copy in
  let result = combine ~owner:Attribute.Point ~destination:"dest"
      ~layers:[threshold] [|geometry|] in
  if float_values ~owner:Attribute.Point "dest" result <> [|1.;0.;1.|] then
    fail "Attribute Combine threshold-half"

let test_tuple_conversion_and_creation () =
  let source3 = Packed.Float3.Private.of_owned_exn
      ~x:[|3.;0.|] ~y:[|4.;0.|] ~z:[|0.;2.|] in
  let geometry = Ops.points [|(0.,0.,0.); (1.,0.,0.)|]
      |> add (Attribute.Float [|0.;0.|]) ~owner:Attribute.Point ~name:"scalar"
      |> add (Attribute.Float3 source3) ~owner:Attribute.Point ~name:"vector"
      |> add (Attribute.Float [|2.;-3.|]) ~owner:Attribute.Point ~name:"factor" in
  let scalar = combine ~owner:Attribute.Point ~destination:"scalar"
      ~layers:[Attribute_ops.combine_layer ~source:"vector"
        Attribute_ops.Combine_copy] [|geometry|] in
  if float_values ~owner:Attribute.Point "scalar" scalar <> [|5.;2.|] then
    fail "Attribute Combine vector length to scalar";
  let vector = combine ~owner:Attribute.Point ~destination:"vector"
      ~layers:[Attribute_ops.combine_layer ~source:"factor"
        Attribute_ops.Combine_copy] [|geometry|] in
  let vector = float3_values ~owner:Attribute.Point "vector" vector in
  if vector.x <> [|2.;-3.|] || vector.y <> [|2.;-3.|]
      || vector.z <> [|2.;-3.|] then
    fail "Attribute Combine scalar replication";
  let source4 = Packed.Float4.of_owned ~x:[|1.;2.|] ~y:[|3.;4.|]
      ~z:[|5.;6.|] ~w:[|7.;8.|] |> Result.get_ok in
  let geometry = add (Attribute.Float4 source4) ~owner:Attribute.Point
      ~name:"source4" geometry in
  let created = combine ~owner:Attribute.Point ~destination:"created"
      ~layers:[Attribute_ops.combine_layer ~source:"source4"
        Attribute_ops.Combine_copy] [|geometry|] in
  let created = float4_values ~owner:Attribute.Point "created" created in
  if created.x <> [|1.;2.|] || created.w <> [|7.;8.|] then
    fail "Attribute Combine missing destination inference";
  let source2 = Packed.Float2.of_owned ~x:[|9.;8.|] ~y:[|7.;6.|]
      |> Result.get_ok in
  let geometry = add (Attribute.Float2 source2) ~owner:Attribute.Point
      ~name:"source2" geometry in
  let extended = combine ~owner:Attribute.Point ~destination:"source4"
      ~layers:[Attribute_ops.combine_layer ~source:"source2"
        Attribute_ops.Combine_copy] [|geometry|] in
  let extended = float4_values ~owner:Attribute.Point "source4" extended in
  if extended.x <> [|9.;8.|] || extended.y <> [|7.;6.|]
      || extended.z <> [|0.;0.|] || extended.w <> [|0.;0.|] then
    fail "Attribute Combine tuple zero extension";
  let constant = combine ~create_missing_as_scalar:true ~owner:Attribute.Point
      ~destination:"constant"
      ~layers:[Attribute_ops.combine_layer ~add:0.25
        Attribute_ops.Combine_copy] [|geometry|] in
  if float_values ~owner:Attribute.Point "constant" constant
      <> [|0.25;0.25|] then fail "Attribute Combine implicit constant"

let test_cross_input_matching () =
  let primary = Ops.points
      [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.); (3.,0.,0.)|]
      |> add (Attribute.Float [|10.;10.;10.;10.|])
           ~owner:Attribute.Point ~name:"dest"
      |> add (Attribute.Int [|1;2;1;9|])
           ~owner:Attribute.Point ~name:"key" in
  let source = Ops.points [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.)|]
      |> add (Attribute.Float [|2.;3.;4.|])
           ~owner:Attribute.Point ~name:"value"
      |> add (Attribute.Float [|1.;0.5;0.25|])
           ~owner:Attribute.Point ~name:"mask"
      |> add (Attribute.Int [|1;2;1|])
           ~owner:Attribute.Point ~name:"key" in
  let layer = Attribute_ops.combine_layer ~source:"value" ~source_input:1
      ~blend_attribute:"mask" ~blend_input:1 Attribute_ops.Combine_copy in
  let result = combine ~match_attribute:"key" ~owner:Attribute.Point
      ~destination:"dest" ~layers:[layer] [|primary;source|] in
  if float_values ~owner:Attribute.Point "dest" result
      <> [|8.5;6.5;8.5;10.|] then
    fail "Attribute Combine integer matching/blend/highest tie";
  let text_primary = primary
      |> add (Attribute.Text [|"oak";"ash";"oak";"none"|])
           ~owner:Attribute.Point ~name:"piece"
  and text_source = source
      |> add (Attribute.Text [|"oak";"ash";"oak"|])
           ~owner:Attribute.Point ~name:"piece" in
  let result = combine ~match_attribute:"piece" ~owner:Attribute.Point
      ~destination:"dest"
      ~layers:[Attribute_ops.combine_layer ~source:"value" ~source_input:1
        Attribute_ops.Combine_copy] [|text_primary;text_source|] in
  if float_values ~owner:Attribute.Point "dest" result
      <> [|4.;3.;4.;0.|] then fail "Attribute Combine text matching";
  let missing_blend = Attribute_ops.combine_layer ~source:"value" ~source_input:1
      ~blend_attribute:"absent" ~blend_input:1 Attribute_ops.Combine_copy in
  let result = combine ~error_on_missing:false ~owner:Attribute.Point
      ~destination:"dest" ~layers:[missing_blend] [|primary;source|] in
  if float_values ~owner:Attribute.Point "dest" result
      <> [|2.;3.;4.;0.|] then fail "Attribute Combine missing blend fallback"

let test_group_post_position_cleanup_and_integer () =
  let geometry = Ops.points
      [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.); (3.,0.,0.)|]
      |> add (Attribute.Float [|0.2;0.8;-0.5;2.|])
           ~owner:Attribute.Point ~name:"dest"
      |> add (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:[|1.;1.;1.;1.|] ~y:[|0.;0.;0.;0.|] ~z:[|0.;0.;0.;0.|]))
           ~owner:Attribute.Point ~name:"velocity"
      |> add (Attribute.Float [|1.;2.;3.;4.|])
           ~owner:Attribute.Point ~name:"temporary" in
  let selection = Group.ordered ~owner:Group.Point ~name:"middle" ~length:4
      [|1;2|] |> Result.get_ok in
  let post = combine ~selection ~overall_scale:2. ~threshold:1.
      ~minimum:0. ~maximum:1. ~owner:Attribute.Point ~destination:"dest"
      ~layers:[] [|geometry|] in
  if float_values ~owner:Attribute.Point "dest" post
      <> [|0.2;1.;0.;2.|] then fail "Attribute Combine grouped postprocess";
  let moved = combine ~owner:Attribute.Point ~destination:"P"
      ~layers:[Attribute_ops.combine_layer ~source:"velocity"
        Attribute_ops.Combine_add] [|geometry|] in
  let positions = Packed.Float3.Private.view (Geometry.positions moved) in
  if positions.x <> [|1.;2.;3.;4.|] then fail "Attribute Combine canonical P";
  let cleaned = combine ~delete_sources:true ~owner:Attribute.Point
      ~destination:"dest"
      ~layers:[Attribute_ops.combine_layer ~source:"temporary"
        Attribute_ops.Combine_add] [|geometry|] in
  let names = Geometry.attributes cleaned |> List.map Attribute.name in
  if names <> ["dest";"velocity"] then
    fail "Attribute Combine cleanup/stable metadata order";
  let huge = (1 lsl 60) + 123 in
  let integer = geometry
      |> add (Attribute.Int [|4;huge;6;8|])
           ~owner:Attribute.Point ~name:"integer"
      |> add (Attribute.Float [|2.;2.;2.;2.|])
           ~owner:Attribute.Point ~name:"integer_source" in
  let first = Group.ordered ~owner:Group.Point ~name:"first" ~length:4 [|0|]
      |> Result.get_ok in
  let integer = combine ~selection:first ~owner:Attribute.Point
      ~destination:"integer"
      ~layers:[Attribute_ops.combine_layer ~source:"integer_source"
        Attribute_ops.Combine_multiply] [|integer|] in
  if int_values ~owner:Attribute.Point "integer" integer
      <> [|8;huge;6;8|] then fail "Attribute Combine checked integer preservation"

let test_other_owners () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;1.;0.|] ~y:[|0.;0.;1.;1.|] ~z:(Array.make 4 0.) in
  let builder = Topology.Builder.create ~point_count:4 () in
  Topology.Builder.add_polygon builder [|0;1;2;3|];
  let geometry = Geometry.create ~positions
      ~topology:(Topology.Builder.freeze builder) () |> Result.get_ok
      |> add (Attribute.Float [|0.;0.;0.;0.|])
           ~owner:Attribute.Vertex ~name:"vertex_dest"
      |> add (Attribute.Float [|1.;2.;3.;4.|])
           ~owner:Attribute.Vertex ~name:"vertex_source"
      |> add (Attribute.Float [|10.|])
           ~owner:Attribute.Primitive ~name:"primitive_dest"
      |> add (Attribute.Float [|3.|])
           ~owner:Attribute.Primitive ~name:"primitive_source"
      |> add (Attribute.Float [|2.|])
           ~owner:Attribute.Detail ~name:"detail_dest"
      |> add (Attribute.Float [|4.|])
           ~owner:Attribute.Detail ~name:"detail_source" in
  let vertex = combine ~owner:Attribute.Vertex ~destination:"vertex_dest"
      ~layers:[Attribute_ops.combine_layer ~source:"vertex_source"
        Attribute_ops.Combine_copy] [|geometry|] in
  if float_values ~owner:Attribute.Vertex "vertex_dest" vertex
      <> [|1.;2.;3.;4.|] then fail "Attribute Combine vertex owner";
  let primitive = combine ~owner:Attribute.Primitive
      ~destination:"primitive_dest"
      ~layers:[Attribute_ops.combine_layer ~source:"primitive_source"
        Attribute_ops.Combine_subtract] [|geometry|] in
  if float_values ~owner:Attribute.Primitive "primitive_dest" primitive
      <> [|7.|] then fail "Attribute Combine primitive owner";
  let detail = combine ~owner:Attribute.Detail ~destination:"detail_dest"
      ~layers:[Attribute_ops.combine_layer ~source:"detail_source"
        Attribute_ops.Combine_multiply] [|geometry|] in
  if float_values ~owner:Attribute.Detail "detail_dest" detail <> [|8.|] then
    fail "Attribute Combine detail owner"

let test_errors_cancellation_and_scale () =
  let geometry = Ops.points [|(0.,0.,0.)|]
      |> add (Attribute.Float [|1.|]) ~owner:Attribute.Point ~name:"dest"
      |> add (Attribute.Text [|"bad"|]) ~owner:Attribute.Point ~name:"text" in
  let expect_invalid result label = match result with
    | Error error when Error.code error = "invalid_combine" -> ()
    | _ -> fail label in
  expect_invalid (Attribute_ops.combine ~owner:Attribute.Point
      ~destination:"dest"
      ~layers:[Attribute_ops.combine_layer ~source:"text"
        Attribute_ops.Combine_copy] ~geometries:[|geometry|] ())
    "Attribute Combine accepted text arithmetic";
  expect_invalid (Attribute_ops.combine ~minimum:2. ~maximum:1.
      ~owner:Attribute.Point ~destination:"dest" ~layers:[]
      ~geometries:[|geometry|] ())
    "Attribute Combine accepted inverted clamps";
  let skipped = Attribute_ops.combine ~error_on_missing:false
      ~owner:Attribute.Point ~destination:"dest"
      ~layers:[Attribute_ops.combine_layer ~source:"absent"
        Attribute_ops.Combine_add] ~geometries:[|geometry|] () |> get_ok in
  if skipped != geometry then
    fail "Attribute Combine missing-source skip did not preserve identity";
  let cancelled = Cancel.create () in Cancel.cancel cancelled;
  (match Attribute_ops.combine ~cancel:cancelled ~owner:Attribute.Point
      ~destination:"dest" ~layers:[] ~geometries:[|geometry|] () with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "cancelled Attribute Combine published output");
  let count = 200_003 in
  let points = Array.init count (fun point -> float_of_int point, 0., 0.) in
  let source4 = Packed.Float4.of_owned
      ~x:(Array.init count (fun point -> float_of_int (point land 255)))
      ~y:(Array.init count (fun point -> float_of_int (point land 127)))
      ~z:(Array.init count (fun point -> float_of_int (point land 63)))
      ~w:(Array.make count 1.) |> Result.get_ok in
  let geometry = Ops.points points
      |> add (Attribute.Float4 source4) ~owner:Attribute.Point ~name:"source4"
      |> add (Attribute.Float (Array.init count (fun point ->
        float_of_int (point land 7) /. 7.)))
           ~owner:Attribute.Point ~name:"mask" in
  let layers = [
    Attribute_ops.combine_layer ~source:"source4" Attribute_ops.Combine_copy;
    Attribute_ops.combine_layer ~add:0.25 ~blend:0.5
      Attribute_ops.Combine_add;
    Attribute_ops.combine_layer ~source:"mask" ~blend_attribute:"mask"
      Attribute_ops.Combine_multiply;
  ] in
  let run domains = Parallel.run ~domains (fun () ->
    Attribute_ops.combine ~grain:257 ~owner:Attribute.Point
      ~destination:"output" ~layers ~geometries:[|geometry|] () |> get_ok) in
  let one = float4_values ~owner:Attribute.Point "output" (run 1)
  and four = float4_values ~owner:Attribute.Point "output" (run 4) in
  if one.x <> four.x || one.y <> four.y || one.z <> four.z || one.w <> four.w
  then fail "200k Attribute Combine one/four-domain exactness"

let () =
  test_operations ();
  test_processing_and_blend ();
  test_tuple_conversion_and_creation ();
  test_cross_input_matching ();
  test_group_post_position_cleanup_and_integer ();
  test_other_owners ();
  test_errors_cancellation_and_scale ();
  print_endline "attribute combine tests passed"
