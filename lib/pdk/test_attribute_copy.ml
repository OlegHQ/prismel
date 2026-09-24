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

let text_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Text values -> values
       | _ -> fail ("wrong text storage for " ^ name))
  | None -> fail ("missing " ^ name)

let float2_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float2 values -> Packed.Float2.Private.view values
       | _ -> fail ("wrong float2 storage for " ^ name))
  | None -> fail ("missing " ^ name)

let float4_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float4 values -> Packed.Float4.Private.view values
       | _ -> fail ("wrong float4 storage for " ^ name))
  | None -> fail ("missing " ^ name)

let positions geometry = Packed.Float3.Private.view (Geometry.positions geometry)

let test_cyclic_order_and_rename () =
  let source = Ops.points [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.)|]
      |> add (Attribute.Float [|10.; 20.; 30.|])
           ~owner:Attribute.Point ~name:"weight"
      |> add (Attribute.Text [|"a"; "b"; "c"|])
           ~owner:Attribute.Point ~name:"label"
      |> add (Attribute.Float4 (Packed.Float4.of_owned
        ~x:[|1.;2.;3.|] ~y:[|4.;5.;6.|] ~z:[|7.;8.;9.|]
        ~w:[|10.;11.;12.|] |> Result.get_ok))
           ~owner:Attribute.Point ~name:"tangent" in
  let target = Ops.points [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.); (3.,0.,0.)|]
      |> add (Attribute.Float [|100.; 100.; 100.; 100.|])
           ~owner:Attribute.Point ~name:"weight"
      |> add (Attribute.Text [|"x"; "x"; "x"; "x"|])
           ~owner:Attribute.Point ~name:"label"
      |> add (Attribute.Float4 (Packed.Float4.of_owned
        ~x:(Array.make 4 0.) ~y:(Array.make 4 0.)
        ~z:(Array.make 4 0.) ~w:(Array.make 4 0.) |> Result.get_ok))
           ~owner:Attribute.Point ~name:"tangent" in
  let source_group = Group.ordered ~owner:Group.Point ~name:"source"
      ~length:3 [|2; 0|] |> Result.get_ok
  and target_group = Group.ordered ~owner:Group.Point ~name:"target"
      ~length:4 [|3; 1; 2|] |> Result.get_ok in
  let copied = Attribute_ops.copy ~grain:1 ~group_owner:Group.Point
      ~source_group ~target_group
      ~rules:[Attribute_ops.copy_rule ~owner:Attribute.Point
        "weight label tangent"]
      ~source ~target () |> get_ok in
  let tangent = float4_values ~owner:Attribute.Point "tangent" copied in
  if float_values ~owner:Attribute.Point "weight" copied
      <> [|100.; 10.; 30.; 30.|]
      || text_values ~owner:Attribute.Point "label" copied
         <> [|"x"; "a"; "c"; "c"|]
      || tangent.x <> [|0.;1.;3.;3.|]
      || tangent.w <> [|0.;10.;12.;12.|] then
    fail "ordered cyclic Attribute Copy";
  let renamed = Attribute_ops.copy ~group_owner:Group.Point
      ~rules:[Attribute_ops.copy_rule ~owner:Attribute.Point
        ~into:"copied_*" "*"] ~source ~target () |> get_ok in
  if float_values ~owner:Attribute.Point "copied_weight" renamed
      <> [|10.; 20.; 30.; 10.|]
      || text_values ~owner:Attribute.Point "copied_label" renamed
         <> [|"a"; "b"; "c"; "a"|] then
    fail "capture-renamed cyclic Attribute Copy"

let test_match_modes () =
  let source = Ops.points
      [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.); (3.,0.,0.)|]
      |> add (Attribute.Int [|1; 2; 1; 3|])
           ~owner:Attribute.Point ~name:"source_key"
      |> add (Attribute.Float [|10.; 20.; 30.; 40.|])
           ~owner:Attribute.Point ~name:"value" in
  let target = Ops.points [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.)|]
      |> add (Attribute.Int [|1; 2; 4|])
           ~owner:Attribute.Point ~name:"target_key"
      |> add (Attribute.Float [|9.; 9.; 9.|])
           ~owner:Attribute.Point ~name:"value" in
  let by_value = Attribute_ops.copy ~grain:1 ~group_owner:Group.Point
      ~match_:(Attribute_ops.By_values { source_attribute = "source_key";
        target_attribute = "target_key" })
      ~rules:[Attribute_ops.copy_rule ~owner:Attribute.Point "value"]
      ~source ~target () |> get_ok in
  if float_values ~owner:Attribute.Point "value" by_value <> [|30.; 20.; 9.|]
  then fail "integer value matching/highest source element";
  let source_group = Group.ordered ~owner:Group.Point ~name:"allowed"
      ~length:4 [|2; 0|] |> Result.get_ok in
  let indexed_target = target
      |> add (Attribute.Int [|2; 1; 0|])
           ~owner:Attribute.Point ~name:"source_element" in
  let to_element = Attribute_ops.copy ~grain:1 ~group_owner:Group.Point
      ~source_group
      ~match_:(Attribute_ops.To_element { target_attribute = "source_element" })
      ~rules:[Attribute_ops.copy_rule ~owner:Attribute.Point "value"]
      ~source ~target:indexed_target () |> get_ok in
  if float_values ~owner:Attribute.Point "value" to_element <> [|30.; 9.; 10.|]
  then fail "to-element source group validation";
  let text_source = source
      |> add (Attribute.Text [|"oak"; "ash"; "oak"; "elm"|])
           ~owner:Attribute.Point ~name:"piece"
  and text_target = target
      |> add (Attribute.Text [|"oak"; "elm"; "none"|])
           ~owner:Attribute.Point ~name:"piece_target" in
  let text = Attribute_ops.copy ~group_owner:Group.Point
      ~match_:(Attribute_ops.By_values { source_attribute = "piece";
        target_attribute = "piece_target" })
      ~rules:[Attribute_ops.copy_rule ~owner:Attribute.Point "value"]
      ~source:text_source ~target:text_target () |> get_ok in
  if float_values ~owner:Attribute.Point "value" text <> [|30.; 40.; 9.|]
  then fail "text value matching"

let two_triangles () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;0.; 2.;3.;2.|] ~y:[|0.;0.;1.; 0.;0.;1.|]
      ~z:(Array.make 6 0.) in
  let topology = Topology.Builder.create ~point_count:6 () in
  Topology.Builder.add_triangle topology 0 1 2;
  Topology.Builder.add_triangle topology 3 4 5;
  Geometry.create ~positions ~topology:(Topology.Builder.freeze topology) ()
  |> Result.get_ok

let quad () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;1.;0.|] ~y:[|0.;0.;1.;1.|] ~z:(Array.make 4 1.) in
  let topology = Topology.Builder.create ~point_count:4 () in
  Topology.Builder.add_polygon topology [|0;1;2;3|];
  Geometry.create ~positions ~topology:(Topology.Builder.freeze topology) ()
  |> Result.get_ok

let test_cross_owner_and_detail () =
  let uv = Packed.Float2.of_owned ~x:[|0.;1.;0.; 0.2;0.8;0.5|]
      ~y:[|0.;0.;1.; 0.3;0.3;0.9|] |> Result.get_ok in
  let source = two_triangles ()
      |> add (Attribute.Float2 uv) ~owner:Attribute.Vertex ~name:"uv"
      |> add (Attribute.Int [|71|]) ~owner:Attribute.Detail ~name:"revision" in
  let target = quad ()
      |> add (Attribute.Float2 (Packed.Float2.of_owned
        ~x:(Array.make 4 (-1.)) ~y:(Array.make 4 (-1.)) |> Result.get_ok))
           ~owner:Attribute.Vertex ~name:"uv"
      |> add (Attribute.Int [|0|]) ~owner:Attribute.Detail ~name:"revision" in
  let source_group = Group.ordered ~owner:Group.Primitive ~name:"faces"
      ~length:2 [|1;0|] |> Result.get_ok in
  let copied domains = Parallel.run ~domains (fun () ->
    Attribute_ops.copy ~grain:1 ~group_owner:Group.Primitive ~source_group
      ~rules:[Attribute_ops.copy_rule ~owner:Attribute.Vertex "uv";
              Attribute_ops.copy_rule ~owner:Attribute.Detail "revision"]
      ~source ~target () |> get_ok) in
  let one = copied 1 and four = copied 4 in
  let uv_one = float2_values ~owner:Attribute.Vertex "uv" one
  and uv_four = float2_values ~owner:Attribute.Vertex "uv" four in
  if uv_one.x <> [|0.2;0.8;0.5;0.2|]
      || uv_one.y <> [|0.3;0.3;0.9;0.3|]
      || uv_one.x <> uv_four.x || uv_one.y <> uv_four.y
      || int_values ~owner:Attribute.Detail "revision" one <> [|71|] then
    fail "primitive-group to vertex/detail projection"

let test_position_copy () =
  let source = Ops.points [|(1.,2.,3.); (4.,5.,6.)|]
  and target = Ops.points [|(0.,0.,0.); (0.,0.,0.); (0.,0.,0.)|] in
  let copied = Attribute_ops.copy ~allow_position:true ~group_owner:Group.Point
      ~rules:[Attribute_ops.copy_rule ~owner:Attribute.Point "P"]
      ~source ~target () |> get_ok in
  let p = positions copied in
  if p.x <> [|1.;4.;1.|] || p.y <> [|2.;5.;2.|]
      || p.z <> [|3.;6.;3.|] then fail "canonical P cyclic copy";
  let excluded = Attribute_ops.copy ~group_owner:Group.Point
      ~rules:[Attribute_ops.copy_rule ~owner:Attribute.Point "P"]
      ~source ~target () |> get_ok in
  if excluded != target then fail "P was not excluded by default";
  let renamed = Attribute_ops.copy ~allow_position:true ~group_owner:Group.Point
      ~rules:[Attribute_ops.copy_rule ~owner:Attribute.Point
        ~into:"source_P" "P"] ~source ~target () |> get_ok in
  (match Geometry.find_attribute ~owner:Attribute.Point "source_P" renamed with
   | Some attribute ->
       (match Attribute.Private.storage attribute with
        | Attribute.Float3 values ->
            let values = Packed.Float3.Private.view values in
            if values.x <> [|1.;4.;1.|] then fail "renamed P payload"
        | _ -> fail "renamed P storage")
   | None -> fail "renamed P missing")

let test_identity_sharing () =
  let source = Ops.points [|(1.,2.,3.); (4.,5.,6.); (7.,8.,9.)|]
      |> add (Attribute.Float [|0.25; 0.5; 0.75|])
           ~owner:Attribute.Point ~name:"weight" in
  let target = Ops.points [|(0.,0.,0.); (0.,0.,0.); (0.,0.,0.)|] in
  let source_weight = match Geometry.find_attribute ~owner:Attribute.Point
      "weight" source with
    | Some attribute -> attribute
    | None -> fail "identity source weight missing" in
  let copied = Attribute_ops.copy ~allow_position:true ~group_owner:Group.Point
      ~rules:[Attribute_ops.copy_rule ~owner:Attribute.Point "P weight"]
      ~source ~target () |> get_ok in
  let copied_weight = match Geometry.find_attribute ~owner:Attribute.Point
      "weight" copied with
    | Some attribute -> attribute
    | None -> fail "identity copied weight missing" in
  if Attribute.storage_id copied_weight <> Attribute.storage_id source_weight then
    fail "identity Attribute Copy did not structurally share attribute storage";
  if Geometry.positions copied != Geometry.positions source then
    fail "identity Attribute Copy did not structurally share canonical P"

let test_errors_and_scale () =
  let source = Ops.points [|(0.,0.,0.)|]
      |> add (Attribute.Float [|1.|]) ~owner:Attribute.Point ~name:"value"
  and target = Ops.points [|(0.,0.,0.)|] in
  (match Attribute_ops.copy ~group_owner:Group.Point
      ~rules:[Attribute_ops.copy_rule ~owner:Attribute.Point
        ~into:"bad" "*"] ~source ~target () with
   | Error error when Error.code error = "invalid_copy" -> ()
   | _ -> fail "Attribute Copy accepted mismatched rewrite wildcards");
  (match Attribute_ops.copy ~group_owner:Group.Vertex
      ~match_:(Attribute_ops.By_values { source_attribute="key";
        target_attribute="key" })
      ~rules:[Attribute_ops.copy_rule ~owner:Attribute.Point "value"]
      ~source ~target () with
   | Error error when Error.code error = "invalid_copy" -> ()
   | _ -> fail "Attribute Copy accepted vertex value matching");
  let cancelled = Cancel.create () in Cancel.cancel cancelled;
  (match Attribute_ops.copy ~cancel:cancelled ~group_owner:Group.Point
      ~rules:[Attribute_ops.copy_rule ~owner:Attribute.Point "value"]
      ~source ~target () with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "cancelled Attribute Copy published output");
  let count = 100_003 in
  let points = Array.init count (fun index -> float_of_int index, 0., 0.) in
  let source = Ops.points points
      |> add (Attribute.Float (Array.init count float_of_int))
           ~owner:Attribute.Point ~name:"value"
      |> add (Attribute.Int (Array.init count (fun index -> index lxor 0x55aa)))
           ~owner:Attribute.Point ~name:"id" in
  let target = Ops.points points in
  let run domains = Parallel.run ~domains (fun () ->
    Attribute_ops.copy ~grain:257 ~group_owner:Group.Point
      ~rules:[Attribute_ops.copy_rule ~owner:Attribute.Point "value id"]
      ~source ~target () |> get_ok) in
  let one = run 1 and four = run 4 in
  if float_values ~owner:Attribute.Point "value" one
      <> float_values ~owner:Attribute.Point "value" four
      || int_values ~owner:Attribute.Point "id" one
         <> int_values ~owner:Attribute.Point "id" four
      || float_values ~owner:Attribute.Point "value" one
         <> Array.init count float_of_int then
    fail "100k Attribute Copy scale/domain exactness"

let () =
  test_cyclic_order_and_rename ();
  test_match_modes ();
  test_cross_owner_and_detail ();
  test_position_copy ();
  test_identity_sharing ();
  test_errors_and_scale ();
  print_endline "attribute copy tests passed"
