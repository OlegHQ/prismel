open Flow
open Port_type

let ok = function Ok value -> value | Error error -> failwith (Diagnostic.to_string error)
let changed node changes = fst (ok (Value_kind.apply_parameters node changes))
let output node = ok (Value_kind.eval ~time:2. node)
let () =
  List.iter (fun kind ->
    assert (ok (Value_kind.of_key (Value_kind.key kind)) = kind);
    let node = Value_kind.make kind in
    assert (Value_kind.kind node = kind);
    assert (List.for_all (fun (field : Param.field_view) -> field.primary && field.current = field.default)
      (Value_kind.fields node));
    let same, effects = ok (Value_kind.apply_parameters node []) in
    assert (same == node && not (Param.has_effects effects));
    assert (List.map (fun (name,value) -> name, value_type value) (output node) = Value_kind.outputs kind))
    Value_kind.all;
  assert (Result.is_error (Value_kind.of_key "sop/time"));
  assert (output (Value_kind.make Time) = ["t", Float_value 2.]);
  assert (output (Value_kind.make Value) = ["out", Float_value 0.]);
  let value = Value_kind.make Value in
  let same, effects = ok (Value_kind.apply_parameters value ["v", Param.Float_value 0.]) in
  assert (same == value && not (Param.has_effects effects));
  let next = changed value ["v", Param.Float_value 5.] in
  assert (Value_kind.parameter_key next <> Value_kind.parameter_key value);
  assert (output value = ["out", Float_value 0.] && output next = ["out", Float_value 5.]);
  List.iter (fun changes -> assert (Result.is_error (Value_kind.apply_parameters value changes)))
    [["unknown", Param.Float_value 1.]; ["v", Param.Int_value 1]; ["v", Param.Float_value nan]];
  List.iter (fun (name, operator) ->
    let node = changed (Value_kind.make Math)
      ["op", Param.Choice_value name; "a", Param.Float_value (-2.); "b", Param.Float_value 3.] in
    let unary = Expr.arity operator = 1 in
    assert (Value_kind.field_active node ~name:"b" = not unary);
    let expected = ok (Expr.apply operator (if unary then [-2.] else [-2.;3.])) in
    assert (output node = ["out", Float_value expected])) Expr.operators;
  let unary = changed (Value_kind.make Math) ["op", Param.Choice_value "sin"; "b", Param.Float_value 7.] in
  let binary = changed unary ["op", Param.Choice_value "add"] in
  assert (output binary = ["out", Float_value 7.]);
  assert (List.length (Value_kind.fields unary) = 3);
  let vector = changed (Value_kind.make Combine_xyz)
    ["x", Param.Float_value 1.; "y", Param.Float_value 2.; "z", Param.Float_value 3.] in
  assert (output vector = ["out", Vec3_value (1.,2.,3.)]);
  let separate = changed (Value_kind.make Separate_xyz)
    ["v_x", Param.Float_value 1.; "v_y", Param.Float_value 2.; "v_z", Param.Float_value 3.] in
  assert (output separate = ["x", Float_value 1.; "y", Float_value 2.; "z", Float_value 3.]);
  assert (List.map (fun (field : Param.field_view) -> field.vec3) (Value_kind.fields separate)
    = [Some ("v",0); Some ("v",1); Some ("v",2)]);
  let remap = changed (Value_kind.make Remap)
    ["from_min", Param.Float_value 2.; "from_max", Param.Float_value (-2.);
     "to_min", Param.Float_value 10.; "to_max", Param.Float_value 20.; "v", Param.Float_value 0.] in
  assert (output remap = ["out", Float_value 15.]);
  let extrapolated = changed remap ["v", Param.Float_value 4.] in
  assert (output extrapolated = ["out", Float_value 5.]);
  assert (output (changed extrapolated ["clamp", Param.Bool_value true]) = ["out", Float_value 10.]);
  assert (output (changed remap ["from_max", Param.Float_value 2.]) = ["out", Float_value 10.]);
  List.iter (fun id -> assert (Result.is_error (Graph.node ~id Value_kind.Time))) [0; -1; max_int];
  let a = ok (Graph.node ~id:2 Value_kind.Time) and b = ok (Graph.node ~id:1 ~label:"scalar" Value_kind.Value) in
  let graph = ok (Graph.add_node a Graph.empty) |> Graph.add_node b |> ok in
  assert (List.map (fun (node : Graph.node) -> node.id) (Graph.inspect graph) = [1;2]);
  assert (Graph.outputs a = ["t", Float]);
  assert (Result.is_error (Graph.add_node a graph));
  assert (Result.is_error (Graph.relabel graph ~node_id:9 "absent"));
  assert (ok (Graph.relabel graph ~node_id:1 "scalar") == graph);
  let same, _ = ok (Graph.apply_parameters graph ~node_id:1 ["v", Param.Float_value 0.]) in
  assert (same == graph);
  let next, effects = ok (Graph.apply_parameters graph ~node_id:1 ["v", Param.Float_value 3.]) in
  assert (effects.cook);
  assert (output (Option.get (Graph.find next ~node_id:1)).parameters = ["out", Float_value 3.]);
  assert (output (Option.get (Graph.find graph ~node_id:1)).parameters = ["out", Float_value 0.]);
  assert (Graph.find (Graph.remove_nodes [1;9] next) ~node_id:1 = None);
  print_endline "Flow value graph: six schemas, all math ops, vectors, remap and immutable identity pass"
