open Flow_sop
let ok = function Ok value -> value | Error diagnostic -> failwith (Flow.Diagnostic.to_string diagnostic)
let rejected code = function
  | Ok _ -> failwith ("Expected " ^ code)
  | Error diagnostic -> assert (diagnostic.Flow.Diagnostic.code = code)
let checked catalog (printed : Print.t) =
  match Flow.Check.check catalog printed.text with
  | Some _, diagnostics when List.for_all (fun (diagnostic : Flow.Diagnostic.t) ->
      diagnostic.severity = Flow.Diagnostic.Warning) diagnostics -> ()
  | _, diagnostics -> failwith (printed.text ^ "\n" ^
      String.concat "; " (List.map Flow.Diagnostic.to_string diagnostics))

type parameters = { a : float; count : int; on : bool; x : float; y : float; z : float; text : string }
let default = {a = 1.; count = 0; on = false; x = 0.; y = 0.; z = 0.; text = "plain"}
let schema = Param.schema ~name:"overlay-test" ~default
  [Param.field ~name:"a" ~kind:(Param.floating ~min:0. ~max:2. ~hard_min:0. ~hard_max:4. ()) ~default:1.
    ~folder:["First"] ~get:(fun p -> p.a) ~set:(fun a p -> {p with a}) ();
   Param.field ~name:"count" ~kind:(Param.integer ~min:0 ~max:10 ~hard_min:0 ~hard_max:10 ()) ~default:0
     ~folder:["Second"] ~get:(fun p -> p.count) ~set:(fun count p -> {p with count}) ();
   Param.field ~name:"on" ~kind:Param.Toggle ~default:false ~folder:["Second"]
     ~get:(fun p -> p.on) ~set:(fun on p -> {p with on}) ();
   Param.field ~name:"x" ~vec3:("position",0) ~kind:(Param.floating ~min:0. ~max:2. ()) ~default:0.
     ~get:(fun p -> p.x) ~set:(fun x p -> {p with x}) ();
   Param.field ~name:"y" ~vec3:("position",1) ~kind:(Param.floating ~min:0. ~max:2. ()) ~default:0.
     ~get:(fun p -> p.y) ~set:(fun y p -> {p with y}) ();
   Param.field ~name:"z" ~vec3:("position",2) ~kind:(Param.floating ~min:0. ~max:2. ()) ~default:0.
     ~get:(fun p -> p.z) ~set:(fun z p -> {p with z}) ();
   Param.field ~name:"text" ~kind:Param.Text ~default:"plain" ~get:(fun p -> p.text) ~set:(fun text p -> {p with text}) ()]
let rec build p =
  let raw = Procedural.Sop.points [|p.a +. p.x, p.y +. float_of_int p.count, p.z|] in
  Procedural.Node.parameterize ~schema ~values:p ~rebuild:(fun ~label:_ ~inputs:_ p -> build p) raw
let port node path = Port.{node; path}
let geometry_bytes geometry =
  let open Pdk in
  let encode value = Marshal.to_string value [Marshal.No_sharing] in
  let attribute (attribute : Attribute.t) =
    let payload = match Attribute.storage attribute with
      | Float values -> encode values | Int values -> encode values | Text values -> encode values
      | Int_array values -> encode (Packed.Int_array.Private.view values)
      | Float_array values -> encode (Packed.Float_array.Private.view values)
      | Float2 values -> let v = Packed.Float2.Private.view values in encode (v.x,v.y)
      | Float3 values -> let v = Packed.Float3.Private.view values in encode (v.x,v.y,v.z)
      | Float4 values -> let v = Packed.Float4.Private.view values in encode (v.x,v.y,v.z,v.w) in
    Attribute.owner attribute, Attribute.name attribute, Attribute.kind_name attribute, payload in
  let groups = List.map (fun group -> Group.owner group, Group.name group,
    Array.init (Group.length group) (fun index -> Group.mem index group), Group.ordered_elements group) (Geometry.groups geometry) in
  let edges = List.map (fun group -> Edge_group.name group,
    Array.init (Edge_group.length group) (fun index -> Edge_group.mem index group)) (Geometry.edge_groups geometry) in
  let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  encode (positions.x,positions.y,positions.z,Topology.Private.view (Geometry.topology geometry),
    List.map attribute (Geometry.attributes geometry),groups,edges)
let () =
  List.iter (fun geometry -> List.iter (fun driven -> List.iter (fun pin ->
    List.iter (fun active -> List.iter (fun overridden -> List.iter (fun primary ->
      let expected = if geometry || driven then true else match pin with
        | Some value -> value | None -> active && (overridden || primary) in
      assert (Exposure.shown ~geometry ~driven ~pin ~active ~overridden ~primary () = expected))
      [false;true]) [false;true]) [false;true]) [None;Some false;Some true]) [false;true]) [false;true];
  let fields = Param.view schema default in
  let rows = ok (Port.parameters fields) in
  assert (List.map (fun parameter -> parameter.Port.path) rows = ["a";"count";"on";"position";"text"]);
  assert (Exposure.primary ~schema:fields (ok (Port.find_parameter rows "a")));
  assert (not (Exposure.primary ~schema:fields (ok (Port.find_parameter rows "count"))));
  rejected "E_PORT" (Port.find_parameter rows "x");
  assert (Port.literal (ok (Port.find_parameter rows "position.y")) = Port.Scalar (Param.Float_value 0.));
  let normalized name value = fst (ok (Port.normalize (ok (Port.find_parameter rows name)) value)) in
  assert (normalized "a" (Flow.Port_type.Float_value 8.) = Flow.Port_type.Float_value 4.);
  assert (normalized "count" (Flow.Port_type.Float_value 2.5) = Flow.Port_type.Int_value 3);
  assert (normalized "count" (Flow.Port_type.Float_value 1e100) = Flow.Port_type.Int_value 10);
  assert (normalized "on" (Flow.Port_type.Float_value (-2.)) = Flow.Port_type.Bool_value true);
  assert (normalized "position" (Flow.Port_type.Int_value 2) = Flow.Port_type.Vec3_value (2.,2.,2.));
  rejected "E_TYPE" (Port.normalize (ok (Port.find_parameter rows "text")) (Flow.Port_type.Float_value 1.));
  rejected "E_TYPE" (Port.normalize (ok (Port.find_parameter rows "a")) (Flow.Port_type.Float_value nan));
  let malformed = List.filter (fun (field : Param.field_view) -> field.name <> "y") fields in
  rejected "E_VEC3" (Port.parameters malformed);
  let node = build default in
  let id = Procedural.Node.id node in
  let base = Network.of_geometry (Procedural.Edit_graph.of_graph node) in
  assert (ok (Network.validate base) = ());
  let check_parameters = List.map (fun parameter ->
    Flow.Check.{name = parameter.Port.path; label = parameter.path;
      ty = parameter.ty;
      fields = List.map (fun (field : Param.field_view) ->
        field.name, field.kind, field.default) parameter.fields}) rows in
  let catalog = Flow.Check.{version = 1; kinds = [
    {qualified = "sop/" ^ Procedural.Node.operation node; aliases = [];
      context = Flow.Context.Sop; slots = []; parameters = check_parameters;
      outputs = ["geo", Flow.Port_type.Geometry]}]} in
  let empty = ok (Print.network ~name:"empty" ~context:Flow.Context.Sop ~catalog
    ~display:None ~definitions:Network.String_map.empty
    (Network.of_geometry Procedural.Edit_graph.empty)) in
  assert (empty.text = "(graph empty :context sop\n  nil)");
  checked catalog empty;
  let printed = ok (Print.network ~name:"demo" ~context:Flow.Context.Sop ~catalog
    ~display:(Some id) ~definitions:Network.String_map.empty base) in
  assert (printed.binding_lines = [id, 2]);
  assert (printed.text = "(graph demo :context sop\n  (let* [points (points)]\n    points))");
  checked catalog printed;
  let a = Procedural.Node.relabel "1 Weird" (build default) in
  let b = Procedural.Node.relabel "1 Weird" (build default) in
  let merged = Procedural.Sop.merge ~label:"t" [a; b] in
  let merge_kind = Flow.Check.{qualified = "sop/merge"; aliases = [];
    context = Flow.Context.Sop;
    slots = [{name = "in0"; required = true}; {name = "in1"; required = true}];
    parameters = []; outputs = ["geo", Flow.Port_type.Geometry]} in
  let catalog_with_merge = Flow.Check.{catalog with kinds = merge_kind :: catalog.kinds} in
  let printed_merge = ok (Print.network ~name:"demo" ~context:Flow.Context.Sop
    ~catalog:catalog_with_merge ~display:(Some (Procedural.Node.id merged))
    ~definitions:Network.String_map.empty
    (Network.of_geometry (Procedural.Edit_graph.of_graph merged))) in
  let checked_merge = fst (Flow.Check.check catalog_with_merge printed_merge.text)
    |> Option.get in
  assert (List.map (fun (binding : Flow.Check.binding) -> binding.name)
    checked_merge.graph.bindings = ["n1_weird"; "n1_weird_2"; "n_t"]);
  let second_only = Procedural.Edit_graph.of_graph merged
    |> Procedural.Edit_graph.disconnect ~consumer:(Procedural.Node.id merged)
      ~input_index:0 |> Result.get_ok in
  let printed_second = ok (Print.network ~name:"demo" ~context:Flow.Context.Sop
    ~catalog:catalog_with_merge ~display:(Some (Procedural.Node.id merged))
    ~definitions:Network.String_map.empty (Network.of_geometry second_only)) in
  checked catalog_with_merge printed_second;
  let consumer = Procedural.Sop.null node in
  let consumer_id = Procedural.Node.id consumer in
  let instance : Network.instance = {definition = "compound_1";
    literals = Network.String_map.empty} in
  let compound = ok (Network.of_parts
    ~geometry:(Procedural.Edit_graph.of_graph consumer)
    ~values:Flow.Graph.empty ~drives:Port.Map.empty
    ~geometry_outputs:Port.Map.empty
    ~instances:(Network.Int_map.singleton id instance)) in
  let target = port consumer_id "in0" in
  let routed = ok (Network.connect_geometry ~source:(port id "result")
    ~consumer:consumer_id ~input_index:0 compound) in
  assert (Network.geometry_source routed target = Some (port id "result"));
  let fragment = ok (Network.copy_nodes [id; consumer_id] routed) in
  let pasted, mapping = ok (Network.paste fragment routed) in
  assert (Network.geometry_source pasted (port (List.assoc consumer_id mapping) "in0")
    = Some (port (List.assoc id mapping) "result"));
  let compound_routed = routed in
  let routed = ok (Network.connect_geometry ~source:(port id "geo")
    ~consumer:consumer_id ~input_index:0 routed) in
  assert (Network.geometry_source routed target = Some (port id "geo")
    && Port.Map.is_empty routed.geometry_outputs);
  let disconnected = ok (Network.disconnect ~target
    (ok (Network.connect_geometry ~source:(port id "result")
      ~consumer:consumer_id ~input_index:0 routed))) in
  assert (Network.geometry_source disconnected target = None
    && Port.Map.is_empty disconnected.geometry_outputs);
  let marker operation inputs = Procedural.Node.Private.make ~operation
    ~version:1 ~parameters:"" ~cook_mode:Procedural.Node.Generic
    ~dependencies:Procedural.Context.Dependencies.static ~inputs
    (fun ~node_id:_ _ _ -> Error (Procedural.Diagnostic.error
      ~code:"E_INTERFACE" "Interface nodes must be flattened")) in
  let inner_box = build default in
  let inputs_marker = marker "flow_inputs" [||] in
  let outputs_marker = marker "flow_outputs" [|inner_box|] in
  let body_geometry = Procedural.Edit_graph.of_graph outputs_marker
    |> Procedural.Edit_graph.add_node inputs_marker |> Result.get_ok in
  let definition : Network.definition = {
    name = "compound_1"; context = Flow.Context.Sop;
    inputs = [];
    outputs = [{name = "result"; ty = Flow.Port_type.Geometry;
      default = None; label = "Result"; soft = None}];
    body = Network.of_geometry body_geometry} in
  let compiled, compiled_ids = ok (Compile.flatten
    ~definitions:(Network.String_map.singleton definition.name definition)
    ~compiled_ids:Instance_path.Map.empty compound_routed) in
  let inner_id = Instance_path.Map.find [id; Procedural.Node.id inner_box]
    compiled_ids in
  assert (Procedural.Edit_graph.find compiled.geometry ~node_id:id = None
    && Procedural.Edit_graph.inputs compiled.geometry ~node_id:consumer_id
      = Some [|Some inner_id|]
    && Procedural.Edit_graph.find compiled.geometry ~node_id:inner_id <> None);
  let cook_graph graph =
    let session = Procedural.Session.create ~max_entries:16
      ~max_payload_bytes:1048576 |> Result.get_ok in
    Fun.protect ~finally:(fun () -> Procedural.Session.close session) (fun () ->
      let context = Procedural.Context.create () |> Result.get_ok in
      let graph = Procedural.Edit_graph.compile graph |> Result.get_ok in
      let result = Procedural.Session.cook session ~context graph |> Result.get_ok in
      geometry_bytes result.geometry) in
  assert (cook_graph compiled.geometry = cook_graph
    (Procedural.Edit_graph.of_graph (Procedural.Sop.null inner_box)));
  rejected "E_IDS" (Compile.flatten ~allocate:false
    ~definitions:(Network.String_map.singleton definition.name definition)
    ~compiled_ids:Instance_path.Map.empty compound_routed);
  let again, same_ids = ok (Compile.flatten ~allocate:false
    ~definitions:(Network.String_map.singleton definition.name definition)
    ~compiled_ids compound_routed) in
  assert (same_ids = compiled_ids
    && Procedural.Edit_graph.inputs again.geometry ~node_id:consumer_id
      = Some [|Some inner_id|]);
  let unrelated = build default in
  let changed_geometry = Procedural.Edit_graph.add_node unrelated
    compound_routed.geometry |> Result.get_ok in
  let changed = ok (Network.with_geometry changed_geometry compound_routed) in
  let changed_flat, stable_ids = ok (Compile.flatten
    ~definitions:(Network.String_map.singleton definition.name definition)
    ~compiled_ids changed) in
  assert (stable_ids = compiled_ids
    && Procedural.Edit_graph.inputs changed_flat.geometry ~node_id:consumer_id
      = Some [|Some inner_id|]);
  let passthrough_inputs = marker "flow_inputs" [||] in
  let passthrough_outputs = marker "flow_outputs" [|passthrough_inputs|] in
  let passthrough_body = Network.of_geometry
    (Procedural.Edit_graph.of_graph passthrough_outputs) in
  let passthrough_body = ok (Network.connect_geometry
    ~source:(port (Procedural.Node.id passthrough_inputs) "incoming")
    ~consumer:(Procedural.Node.id passthrough_outputs) ~input_index:0
    passthrough_body) in
  let geometry_port name : Network.interface_port =
    {name; ty = Flow.Port_type.Geometry; default = None; label = name; soft = None} in
  let passthrough : Network.definition = {
    name = "pass"; context = Flow.Context.Sop;
    inputs = [geometry_port "incoming"];
    outputs = [geometry_port "result"];
    body = passthrough_body} in
  let source = build default in
  let first = Procedural.Sop.null source in
  let second = Procedural.Sop.null first in
  let downstream = Procedural.Sop.null second in
  let first_id = Procedural.Node.id first and second_id = Procedural.Node.id second
  and downstream_id = Procedural.Node.id downstream in
  let instance : Network.instance = {definition = "pass";
    literals = Network.String_map.empty} in
  let chained = ok (Network.of_parts
    ~geometry:(Procedural.Edit_graph.of_graph downstream)
    ~values:Flow.Graph.empty ~drives:Port.Map.empty
    ~geometry_outputs:Port.Map.empty
    ~instances:(Network.Int_map.of_list [first_id, instance; second_id, instance])) in
  let chained = ok (Network.connect_geometry
    ~source:(port first_id "result") ~consumer:second_id ~input_index:0 chained) in
  let chained = ok (Network.connect_geometry
    ~source:(port second_id "result") ~consumer:downstream_id ~input_index:0 chained) in
  let compiled, _ = ok (Compile.flatten
    ~definitions:(Network.String_map.singleton passthrough.name passthrough)
    ~compiled_ids:Instance_path.Map.empty chained) in
  assert (Procedural.Edit_graph.inputs compiled.geometry ~node_id:downstream_id
    = Some [|Some (Procedural.Node.id source)|]
    && cook_graph compiled.geometry = cook_graph
      (Procedural.Edit_graph.of_graph (Procedural.Sop.null source)));
  let network, time = ok (Network.add_value_node Flow.Value_kind.Time base) in
  assert (time <> id);
  let network, vector = ok (Network.add_value_node Flow.Value_kind.Combine_xyz network) in
  let network, math = ok (Network.add_value_node Flow.Value_kind.Math network) in
  let network = ok (Network.connect_value ~source:(port time "t") ~target:(port math "a") network) in
  let network = ok (Network.connect_value ~source:(port math "out") ~target:(port id "a") network) in
  let printed = ok (Print.network ~name:"demo" ~context:Flow.Context.Sop ~catalog
    ~display:(Some id) ~definitions:Network.String_map.empty network) in
  assert (String.contains printed.text '*');
  checked catalog printed;
  let qualified = ok (Print.network ~qualified:true ~name:"demo"
    ~context:Flow.Context.Sop ~catalog ~display:(Some id)
    ~definitions:Network.String_map.empty network) in
  checked catalog qualified;
  assert (ok (Network.connect_value ~source:(port math "out") ~target:(port id "a") network) == network);
  assert (Network.parameter network (port id "a") |> ok |> Port.literal = Port.Scalar (Param.Float_value 1.));
  rejected "E_TYPE" (Network.connect_value ~source:(port vector "out") ~target:(port id "a") network);
  rejected "E_TYPE" (Network.connect_value ~source:(port id "geo") ~target:(port math "a") network);
  rejected "E_TYPE" (Network.connect_value ~source:(port time "t") ~target:(port id "text") network);
  rejected "E_CYCLE" (Network.connect_value ~source:(port math "out") ~target:(port time "speed") network);
  rejected "E_CYCLE" (Network.connect_value ~source:(port math "out") ~target:(port math "b") network);
  rejected "E_PORT" (Network.connect_value ~source:(port time "wrong") ~target:(port id "a") network);
  let whole = ok (Network.connect_value ~source:(port vector "out") ~target:(port id "position") network) in
  rejected "E_VEC3_CONFLICT" (Network.connect_value ~source:(port time "t") ~target:(port id "position.y") whole);
  let component = ok (Network.connect_value ~source:(port time "t") ~target:(port id "position.y") network) in
  let printed = ok (Print.network ~name:"demo" ~context:Flow.Context.Sop ~catalog
    ~display:(Some id) ~definitions:Network.String_map.empty component) in
  checked catalog printed;
  rejected "E_VEC3_CONFLICT" (Network.connect_value ~source:(port vector "out") ~target:(port id "position") component);
  let literal = ok (Network.set_literal ~target:(port id "position") (Port.Vector (1.,2.,3.)) network) in
  let printed = ok (Print.network ~name:"demo" ~context:Flow.Context.Sop ~catalog
    ~display:(Some id) ~definitions:Network.String_map.empty literal) in
  checked catalog printed;
  rejected "E_TYPE" (Network.set_literal ~target:(port id "count") (Port.Scalar (Param.Float_value 1.5)) network);
  assert (Port.literal (ok (Network.parameter literal (port id "position"))) = Port.Vector (1.,2.,3.));
  assert (Port.literal (ok (Network.parameter network (port id "position"))) = Port.Vector (0.,0.,0.));
  let removed = ok (Network.remove_nodes [math] network) in
  assert (removed.geometry == network.geometry && Port.Map.is_empty removed.drives);
  assert (ok (Network.remove_nodes [-1] network) == network);
  let collision = Flow.Graph.node ~id Flow.Value_kind.Time |> ok |> fun node -> Flow.Graph.add_node node Flow.Graph.empty |> ok in
  rejected "E_DUPLICATE" (Network.of_parts ~geometry:network.geometry ~values:collision
    ~drives:Port.Map.empty ~geometry_outputs:Port.Map.empty
    ~instances:Network.Int_map.empty);
  let restored_id = Procedural.Node.Private.fresh_id () + 10000 in
  let restored = Flow.Graph.node ~id:restored_id Flow.Value_kind.Value |> ok
    |> fun node -> Flow.Graph.add_node node Flow.Graph.empty |> ok in
  ignore (ok (Network.of_parts ~geometry:base.geometry ~values:restored
    ~drives:Port.Map.empty ~geometry_outputs:Port.Map.empty
    ~instances:Network.Int_map.empty));
  assert (Procedural.Node.Private.fresh_id () > restored_id);
  let order = ok (Network.topological_values network) in
  let index id = List.find_index (( = ) id) order |> Option.get in
  assert (index time < index math);
  let fragment = ok (Network.copy_nodes [id;time;math] network) in
  let pasted, mapping = ok (Network.paste fragment network) in
  let mapped id = List.assoc id mapping in
  assert (mapped id <> id && mapped time <> time && mapped math <> math);
  assert (Port.Map.find (port (mapped id) "a") pasted.drives = Drive.Wire {node = mapped math; output = "out"});
  assert (Port.Map.find (port (mapped math) "a") pasted.drives = Drive.Wire {node = mapped time; output = "t"});
  let fragment = ok (Network.copy_nodes [id] network) in
  let pasted, mapping = ok (Network.paste fragment network) in
  assert (not (Port.Map.mem (port (List.assoc id mapping) "a") pasted.drives));
  let fragment = ok (Network.copy_nodes [time;math] network) in
  let pasted, mapping = ok (Network.paste fragment base) in
  assert (pasted.geometry == base.geometry && List.length mapping = 2);
  assert (Port.Map.cardinal pasted.drives = 1);
  rejected "E_UNBOUND" (Network.copy_nodes [-1] network);
  let lane = Value_lane.create () in
  let resolve ?(time = 2.) network = ok (Value_lane.resolve lane ~time network) in
  let field graph name = Procedural.Edit_graph.find graph ~node_id:id |> Option.get
    |> Procedural.Node.parameter_fields |> List.find (fun (field : Param.field_view) -> field.name = name)
    |> fun field -> field.current in
  let at_two = resolve network in
  assert (at_two.time_dependent && field at_two.geometry "a" = Param.Float_value 2.);
  assert (field network.geometry "a" = Param.Float_value 1.);
  let orphan = ok (Network.remove_nodes [id] network) |> resolve in
  assert (Port.Map.find (port math "out") orphan.outputs = Flow.Port_type.Float_value 2.);
  ignore (resolve network);
  let result = Value_lane.resolve lane ~time:2. network in
  assert (Value_lane.resolve lane ~time:2. network == result);
  let at_three = resolve ~time:3. network in
  assert (field at_three.geometry "a" = Param.Float_value 3.);
  let saturated = resolve ~time:100. network in
  assert (field saturated.geometry "a" = Param.Float_value 4.);
  assert ((resolve ~time:101. network).geometry == saturated.geometry);
  let cleared = ok (Network.clear_drive ~target:(port id "a") network) in
  assert (field (resolve cleared).geometry "a" = Param.Float_value 1.);
  let edited = ok (Network.set_literal ~target:(port id "a") (Port.Scalar (Param.Float_value 0.5)) network) in
  assert (field (resolve ~time:3. edited).geometry "a" = Param.Float_value 3.);
  let restored = ok (Network.clear_drive ~target:(port id "a") edited) in
  assert (field (resolve restored).geometry "a" = Param.Float_value 0.5);
  let unrelated = ok (Network.set_literal ~target:(port id "count") (Port.Scalar (Param.Int_value 8)) network) in
  let retained = resolve ~time:3. unrelated in
  assert (field retained.geometry "count" = Param.Int_value 8 && field retained.geometry "a" = Param.Float_value 3.);
  let static = ok (Network.set_expr ~target:(port id "a") (ok (Flow.Expr.parse "1 + 2")) base) in
  let static_result = Value_lane.resolve lane ~time:2. static in
  assert (Value_lane.resolve lane ~time:100. static == static_result);
  assert (not (ok static_result).time_dependent);
  let empty = ok (Network.clear_drive ~target:(port id "a") static) in
  assert ((resolve empty).geometry == empty.geometry);
  Value_lane.reset lane;
  assert ((resolve static).geometry != (ok static_result).geometry);
  let disconnected, _ = ok (Network.add_value_node Flow.Value_kind.Time base) in
  let no_drives = resolve disconnected in
  assert (no_drives.geometry == base.geometry && not no_drives.time_dependent && Port.Map.is_empty no_drives.outputs);
  let expression = ok (Network.set_expr ~target:(port id "a") (ok (Flow.Expr.parse "t * 1e308")) base) in
  assert (field (resolve ~time:0. expression).geometry "a" = Param.Float_value 0.);
  rejected "E_TYPE" (Value_lane.resolve lane ~time:2. expression);
  assert (field (resolve ~time:0. expression).geometry "a" = Param.Float_value 0.);
  let seed = Random.State.make [|0x51A17|] in
  let rec random_expr depth =
    if depth = 0 || Random.State.int seed 4 = 0 then
      if Random.State.bool seed then Flow.Expr.time else
        ok (Flow.Expr.num (float (Random.State.int seed 5 - 2) /. 2.))
    else
      let _, op = List.nth Flow.Expr.operators
        (Random.State.int seed (List.length Flow.Expr.operators)) in
      ok (Flow.Expr.op op (List.init (Flow.Expr.arity op) (fun _ -> random_expr (depth - 1)))) in
  for _ = 1 to 80 do
    let op = snd (List.nth Flow.Expr.operators
      (Random.State.int seed (List.length Flow.Expr.operators))) in
    let expression = ok (Flow.Expr.op op
      (List.init (Flow.Expr.arity op) (fun _ -> random_expr 3))) in
    let expanded, placements = ok (Network.unfold ~target:(port id "a")
      (ok (Network.set_expr ~target:(port id "a") expression base))) in
    assert (placements <> []);
    let folded, removed = ok (Network.fold ~target:(port id "a") expanded) in
    assert (removed <> []);
    assert (Port.Map.find (port id "a") folded.drives = Drive.Expr expression);
    assert (Flow.Graph.inspect folded.values = [])
  done;
  let only_time = ok (Network.set_expr ~target:(port id "a") Flow.Expr.time base) in
  let expanded, placements = ok (Network.unfold ~target:(port id "a") only_time) in
  assert (List.length placements = 1);
  let folded, _ = ok (Network.fold ~target:(port id "a") expanded) in
  assert (Port.Map.find (port id "a") folded.drives = Drive.Expr Flow.Expr.time);
  let twice = ok (Network.set_expr ~target:(port id "a")
    (ok (Flow.Expr.parse "t+t")) base) in
  let expanded, placements = ok (Network.unfold ~target:(port id "a") twice) in
  assert (List.length placements = 2);
  let time_nodes = List.filter (fun (node : Flow.Graph.node) ->
    Flow.Value_kind.kind node.parameters = Flow.Value_kind.Time)
    (Flow.Graph.inspect expanded.values) in
  assert (List.length time_nodes = 1);
  let folded, _ = ok (Network.fold ~target:(port id "a") expanded) in
  assert (Port.Map.find (port id "a") folded.drives =
    Drive.Expr (ok (Flow.Expr.parse "t+t")));
  let only_number = ok (Network.set_expr ~target:(port id "a") (ok (Flow.Expr.num 0.5)) base) in
  let expanded, placements = ok (Network.unfold ~target:(port id "a") only_number) in
  assert (placements = [] && not (Port.Map.mem (port id "a") expanded.drives));
  assert (Port.literal (ok (Network.parameter expanded (port id "a"))) =
    Port.Scalar (Param.Float_value 0.5));
  let plain, plain_id = ok (Network.add_value_node Flow.Value_kind.Value base) in
  let plain = ok (Network.set_literal ~target:(port plain_id "v")
    (Port.Scalar (Param.Float_value 0.75)) plain) in
  let plain = ok (Network.connect_value ~source:(port plain_id "out")
    ~target:(port id "a") plain) in
  let folded, removed = ok (Network.fold ~target:(port id "a") plain) in
  assert (removed = [plain_id] && not (Port.Map.mem (port id "a") folded.drives));
  assert (Port.literal (ok (Network.parameter folded (port id "a"))) =
    Port.Scalar (Param.Float_value 0.75));
  let shared = ok (Network.connect_value ~source:(port math "out")
    ~target:(port id "count") network) in
  rejected "E_FOLD" (Network.fold ~target:(port id "a") shared);
  let remap, remap_id = ok (Network.add_value_node Flow.Value_kind.Remap base) in
  let remap = ok (Network.connect_value ~source:(port remap_id "out")
    ~target:(port id "a") remap) in
  rejected "E_FOLD" (Network.fold ~target:(port id "a") remap);
  let speed, speed_source = ok (Network.add_value_node Flow.Value_kind.Value base) in
  let speed, clock = ok (Network.add_value_node Flow.Value_kind.Time speed) in
  let speed = ok (Network.connect_value ~source:(port speed_source "out")
    ~target:(port clock "speed") speed) in
  let speed = ok (Network.connect_value ~source:(port clock "t")
    ~target:(port id "a") speed) in
  rejected "E_FOLD" (Network.fold ~target:(port id "a") speed);
  let vec = ok (Network.set_literal ~target:(port vector "x") (Port.Scalar (Param.Float_value 1.)) whole) in
  let vec = ok (Network.set_literal ~target:(port vector "y") (Port.Scalar (Param.Float_value 2.)) vec) in
  let vec = ok (Network.set_literal ~target:(port vector "z") (Port.Scalar (Param.Float_value 3.)) vec) in
  let resolved = resolve vec in
  assert (Port.Map.find (port id "position") resolved.applied = Flow.Port_type.Vec3_value (1.,2.,3.));
  assert (field resolved.geometry "x" = Param.Float_value 1. && field resolved.geometry "z" = Param.Float_value 3.);
  let component_value = resolve component in
  assert (field component_value.geometry "x" = Param.Float_value 0.
    && field component_value.geometry "y" = Param.Float_value 2. && field component_value.geometry "z" = Param.Float_value 0.);
  let coerce = ok (Network.set_expr ~target:(port id "count") (ok (Flow.Expr.parse "2.5")) base) in
  let coerce = ok (Network.set_expr ~target:(port id "on") (ok (Flow.Expr.parse "-2")) coerce) in
  let coerce = resolve coerce in
  assert (field coerce.geometry "count" = Param.Int_value 3 && field coerce.geometry "on" = Param.Bool_value true);
  let grid = Procedural.Sop.grid ~columns:128 ~rows:128 ~size:1. () in
  let rec noisy input values =
    Procedural.Sop.noise_displace ~seed:17 ~amplitude:values.a ~frequency:1. input
    |> Procedural.Node.parameterize ~schema ~values
      ~rebuild:(fun ~label:_ ~inputs values -> match inputs with
        | [input] -> noisy input values | _ -> assert false) in
  let noisy_node = noisy grid default in
  let noisy_network = Network.of_geometry (Procedural.Edit_graph.of_graph noisy_node) in
  let noisy_network = ok (Network.set_expr ~target:(port (Procedural.Node.id noisy_node) "a")
    (ok (Flow.Expr.parse "sin(t) * 0.5 + 1")) noisy_network) in
  let cook domains =
    let geometry = (ok (Value_lane.resolve (Value_lane.create ()) ~time:2. noisy_network)).geometry in
    let graph = match Procedural.Edit_graph.compile geometry with Ok graph -> graph | Error error -> failwith error in
    let context = match Procedural.Context.create ~domains ~grain:97 ~seed:42L () with
      | Ok context -> context | Error error -> failwith error in
    let session = match Procedural.Session.create ~max_entries:16 ~max_payload_bytes:(32*1024*1024) with
      | Ok session -> session | Error error -> failwith error in
    Fun.protect ~finally:(fun () -> Procedural.Session.close session) (fun () ->
      match Procedural.Session.cook session ~context graph with
      | Error error -> failwith (Procedural.Diagnostic.error_to_string error)
      | Ok result -> geometry_bytes result.geometry) in
  assert (cook 1 = cook 4);
  let inner = build default in
  let inner_id = Procedural.Node.id inner in
  let grouped, definition, instance = ok (Group.geometry
    ~name:"value_compound" ~selected:[inner_id] ~displayed:(Some inner_id)
    ~definitions:Network.String_map.empty
    (Network.of_geometry (Procedural.Edit_graph.of_graph inner))) in
  let speed : Network.interface_port = {
    name = "speed"; ty = Flow.Port_type.Float;
    default = Some (Port.Scalar (Param.Float_value 1.)); label = "Speed";
    soft = Some (0., 4.)} in
  let output = {speed with name = "speed_out"; label = "Speed out"} in
  let position : Network.interface_port = {
    name = "position"; ty = Flow.Port_type.Vec3;
    default = Some (Port.Vector (1., 1., 1.)); label = "Position";
    soft = Some (0., 4.)} in
  let position_out = {position with name = "position_out";
    label = "Position out"} in
  let definition = {definition with
    inputs = definition.inputs @ [speed; position];
    outputs = definition.outputs @ [output; position_out]} in
  let factories = Compound_node.factories ~name:definition.name
    ~inputs:definition.inputs ~outputs:definition.outputs in
  let marker = Procedural.Edit_graph.inspect definition.body.geometry
    |> List.find (fun (node : Procedural.Edit_graph.node_info) ->
      node.operation = "flow_inputs") in
  let outputs_marker = Procedural.Edit_graph.inspect definition.body.geometry
    |> List.find (fun (node : Procedural.Edit_graph.node_info) ->
      node.operation = "flow_outputs") in
  let body_geometry = Procedural.Edit_graph.rebind_factory ~node_id:marker.id
    (List.hd factories) definition.body.geometry |> Result.get_ok in
  let body_geometry = Procedural.Edit_graph.rebind_factory
    ~node_id:outputs_marker.id (List.nth factories 1) body_geometry
    |> Result.get_ok in
  let body = ok (Network.with_geometry body_geometry definition.body) in
  let body, inner_value = ok (Network.add_value_node Flow.Value_kind.Value body) in
  let body = ok (Network.connect_value ~source:(port marker.id "speed")
    ~target:(port inner_value "v") body) in
  let body = ok (Network.connect_value ~source:(port inner_value "out")
    ~target:(port inner_id "a") body) in
  let body = ok (Network.connect_value ~source:(port inner_value "out")
    ~target:(port outputs_marker.id "speed_out") body) in
  let body = ok (Network.connect_value ~source:(port marker.id "position")
    ~target:(port inner_id "position") body) in
  let body = ok (Network.connect_value ~source:(port marker.id "position")
    ~target:(port outputs_marker.id "position_out") body) in
  let definition = {definition with body} in
  let grouped_geometry = Procedural.Edit_graph.rebind_factory
    ~node_id:instance (List.nth factories 2) grouped.geometry |> Result.get_ok in
  let grouped = ok (Network.with_geometry grouped_geometry grouped) in
  let grouped_base = grouped in
  let printed = ok (Print.network ~name:"demo" ~context:Flow.Context.Sop ~catalog
    ~display:(Some instance)
    ~definitions:(Network.String_map.singleton definition.name definition)
    grouped_base) in
  checked catalog printed;
  let checked_program = fst (Flow.Check.check catalog printed.text) |> Option.get in
  assert ((List.hd checked_program.definitions).outputs =
    List.map (fun (port : Network.interface_port) -> port.name, port.ty)
      definition.outputs);
  assert (List.assoc instance printed.binding_lines > 2);
  let grouped = ok (Network.set_literal ~target:(port instance "speed")
    (Port.Scalar (Param.Float_value 3.)) grouped) in
  let outside = build default in
  let outside_id = Procedural.Node.id outside in
  let geometry = Procedural.Edit_graph.add_node outside grouped.geometry
    |> Result.get_ok in
  let grouped = ok (Network.with_geometry geometry grouped) in
  let grouped = ok (Network.connect_value
    ~source:(port instance "speed_out") ~target:(port outside_id "a")
    grouped) in
  let grouped, vector = ok (Network.add_value_node
    Flow.Value_kind.Combine_xyz grouped) in
  let grouped = ok (Network.set_literal ~target:(port vector "x")
    (Port.Scalar (Param.Float_value 3.)) grouped) in
  let grouped = ok (Network.connect_value
    ~source:(port vector "out") ~target:(port instance "position")
    grouped) in
  let grouped = ok (Network.connect_value
    ~source:(port instance "position_out.x")
    ~target:(port outside_id "position.x") grouped) in
  let grouped, outside_value = ok (Network.add_value_node
    Flow.Value_kind.Value grouped) in
  let grouped = ok (Network.connect_value
    ~source:(port instance "speed_out") ~target:(port outside_value "v")
    grouped) in
  let flat, compiled_ids = ok (Compile.flatten
    ~definitions:(Network.String_map.singleton definition.name definition)
    ~compiled_ids:Instance_path.Map.empty grouped) in
  let cooked = ok (Value_lane.resolve (Value_lane.create ()) ~time:0. flat) in
  let compiled_inner = Instance_path.Map.find [instance; inner_id]
    compiled_ids
  and compiled_value = Instance_path.Map.find [instance; inner_value]
    compiled_ids in
  rejected "E_IDS" (Compile.flatten ~allocate:false
    ~definitions:(Network.String_map.singleton definition.name definition)
    ~compiled_ids:(Instance_path.Map.remove [instance; inner_value]
      compiled_ids) grouped);
  let cyclic = ok (Network.connect_value
    ~source:(port instance "speed_out") ~target:(port instance "speed")
    grouped_base) in
  rejected "E_CYCLE" (Compile.flatten
    ~definitions:(Network.String_map.singleton definition.name definition)
    ~compiled_ids:Instance_path.Map.empty cyclic);
  assert (Flow.Graph.find flat.values ~node_id:compiled_value <> None
    && Port.Map.find (port outside_id "a") flat.drives
       = Drive.Wire {node = compiled_value; output = "out"});
  let field = Procedural.Edit_graph.find cooked.geometry
    ~node_id:compiled_inner |> Option.get
    |> Procedural.Node.parameter_fields
    |> List.find (fun (field : Param.field_view) -> field.name = "a") in
  let outside_field = Procedural.Edit_graph.find cooked.geometry
    ~node_id:outside_id |> Option.get
    |> Procedural.Node.parameter_fields
    |> List.find (fun (field : Param.field_view) -> field.name = "a") in
  let component geometry id name = Procedural.Edit_graph.find geometry ~node_id:id
    |> Option.get |> Procedural.Node.parameter_fields
    |> List.find (fun (field : Param.field_view) -> field.name = name)
    |> fun field -> field.current in
  assert (field.current = Param.Float_value 3.
    && outside_field.current = Param.Float_value 3.
    && component cooked.geometry compiled_inner "x" = Param.Float_value 3.
    && component cooked.geometry outside_id "x" = Param.Float_value 3.
    && Port.Map.find (port outside_value "out") cooked.outputs
       = Flow.Port_type.Float_value 3.);
  assert (cook_graph cooked.geometry = cook_graph (Procedural.Edit_graph.of_graph
    (build {default with a = 3.; x = 3.})));
  let components = ok (Network.clear_drive
    ~target:(port instance "position") grouped) in
  let components, scalar = ok (Network.add_value_node
    Flow.Value_kind.Value components) in
  let components = ok (Network.set_literal ~target:(port scalar "v")
    (Port.Scalar (Param.Float_value 2.)) components) in
  let components = ok (Network.connect_value
    ~source:(port scalar "out") ~target:(port instance "position.x")
    components) in
  let flat, same_ids = ok (Compile.flatten ~allocate:false
    ~definitions:(Network.String_map.singleton definition.name definition)
    ~compiled_ids components) in
  let cooked = ok (Value_lane.resolve (Value_lane.create ()) ~time:0. flat) in
  assert (same_ids = compiled_ids
    && component cooked.geometry compiled_inner "x" = Param.Float_value 2.
    && component cooked.geometry compiled_inner "y" = Param.Float_value 1.
    && component cooked.geometry compiled_inner "z" = Param.Float_value 1.
    && component cooked.geometry outside_id "x" = Param.Float_value 2.);
  let second_node = Procedural.Edit_graph.instantiate_optional
    (List.nth factories 2) [] |> Result.get_ok in
  let second = Procedural.Node.id second_node in
  let geometry = Procedural.Edit_graph.add_node
    ~factory:(List.nth factories 2) second_node grouped.geometry
    |> Result.get_ok in
  let second_instance : Network.instance = {
    definition = definition.name; literals = Network.String_map.empty} in
  let shared = ok (Network.of_parts ~geometry ~values:grouped.values
    ~drives:grouped.drives ~geometry_outputs:grouped.geometry_outputs
    ~instances:(Network.Int_map.add second second_instance grouped.instances)) in
  let shared = ok (Network.set_literal ~target:(port second "speed")
    (Port.Scalar (Param.Float_value 2.)) shared) in
  let second_consumer = Procedural.Sop.null second_node in
  let geometry = Procedural.Edit_graph.add_node second_consumer shared.geometry
    |> Result.get_ok in
  let shared = ok (Network.with_geometry geometry shared) in
  let shared = ok (Network.connect_geometry
    ~source:(port second "result")
    ~consumer:(Procedural.Node.id second_consumer) ~input_index:0 shared) in
  let flat, shared_ids = ok (Compile.flatten
    ~definitions:(Network.String_map.singleton definition.name definition)
    ~compiled_ids shared) in
  let cooked = ok (Value_lane.resolve (Value_lane.create ()) ~time:0. flat) in
  let second_inner = Instance_path.Map.find [second; inner_id] shared_ids in
  assert (Instance_path.Map.find [instance; inner_id] shared_ids = compiled_inner
    && second_inner <> compiled_inner
    && (Procedural.Edit_graph.find cooked.geometry ~node_id:second_inner
      |> Option.get |> Procedural.Node.parameter_fields
      |> List.find (fun (field : Param.field_view) -> field.name = "a")
      |> fun field -> field.current) = Param.Float_value 2.);
  let dynamic = ok (Network.set_expr ~target:(port instance "speed")
    (ok (Flow.Expr.parse "t * 2")) grouped) in
  let flat, same_ids = ok (Compile.flatten ~allocate:false
    ~definitions:(Network.String_map.singleton definition.name definition)
    ~compiled_ids dynamic) in
  let cooked = ok (Value_lane.resolve (Value_lane.create ()) ~time:2. flat) in
  let dynamic_field = Procedural.Edit_graph.find cooked.geometry
    ~node_id:compiled_inner |> Option.get
    |> Procedural.Node.parameter_fields
    |> List.find (fun (field : Param.field_view) -> field.name = "a") in
  assert (same_ids = compiled_ids && cooked.time_dependent
    && dynamic_field.current = Param.Float_value 4.);
  let outer, outer_definition, outer_instance = ok (Group.geometry
    ~name:"outer" ~selected:[instance] ~displayed:(Some instance)
    ~definitions:(Network.String_map.singleton definition.name definition)
    grouped_base) in
  let outer_definition = {outer_definition with
    inputs = outer_definition.inputs @ [speed];
    outputs = outer_definition.outputs @ [output]} in
  let outer_factories = Compound_node.factories
    ~name:outer_definition.name ~inputs:outer_definition.inputs
    ~outputs:outer_definition.outputs in
  let outer_outputs = Procedural.Edit_graph.inspect
    outer_definition.body.geometry
    |> List.find (fun (node : Procedural.Edit_graph.node_info) ->
      node.operation = "flow_outputs") in
  let outer_inputs = Procedural.Edit_graph.inspect
    outer_definition.body.geometry
    |> List.find (fun (node : Procedural.Edit_graph.node_info) ->
      node.operation = "flow_inputs") in
  let body_geometry = Procedural.Edit_graph.rebind_factory
    ~node_id:outer_inputs.id (List.hd outer_factories)
    outer_definition.body.geometry |> Result.get_ok in
  let body_geometry = Procedural.Edit_graph.rebind_factory
    ~node_id:outer_outputs.id (List.nth outer_factories 1)
    body_geometry |> Result.get_ok in
  let body = ok (Network.with_geometry body_geometry outer_definition.body) in
  let body = ok (Network.connect_value
    ~source:(port outer_inputs.id "speed")
    ~target:(port instance "speed") body) in
  let body = ok (Network.connect_value
    ~source:(port instance "speed_out")
    ~target:(port outer_outputs.id "speed_out") body) in
  let outer_definition = {outer_definition with body} in
  let geometry = Procedural.Edit_graph.rebind_factory
    ~node_id:outer_instance (List.nth outer_factories 2)
    outer.geometry |> Result.get_ok in
  let outer = ok (Network.with_geometry geometry outer) in
  let outer = ok (Network.set_literal ~target:(port outer_instance "speed")
    (Port.Scalar (Param.Float_value 2.)) outer) in
  let outside = build default in
  let outside_id = Procedural.Node.id outside in
  let geometry = Procedural.Edit_graph.add_node outside outer.geometry
    |> Result.get_ok in
  let outer = ok (Network.with_geometry geometry outer) in
  let outer = ok (Network.connect_value
    ~source:(port outer_instance "speed_out")
    ~target:(port outside_id "a") outer) in
  let definitions = Network.String_map.empty
    |> Network.String_map.add definition.name definition
    |> Network.String_map.add outer_definition.name outer_definition in
  let flat, nested_ids = ok (Compile.flatten ~definitions
    ~compiled_ids:Instance_path.Map.empty outer) in
  let nested_inner = Instance_path.Map.find
    [outer_instance; instance; inner_id] nested_ids in
  let cooked = ok (Value_lane.resolve (Value_lane.create ()) ~time:0. flat) in
  let number id = Procedural.Edit_graph.find cooked.geometry ~node_id:id
    |> Option.get |> Procedural.Node.parameter_fields
    |> List.find (fun (field : Param.field_view) -> field.name = "a")
    |> fun field -> field.current in
  assert (number nested_inner = Param.Float_value 2.
    && number outside_id = Param.Float_value 2.);
  let selected_sop = build default in
  let selected_id = Procedural.Node.id selected_sop in
  let parent_sop = build default in
  let parent_id = Procedural.Node.id parent_sop in
  let geometry = Procedural.Edit_graph.of_graph selected_sop
    |> Procedural.Edit_graph.add_node parent_sop |> Result.get_ok in
  let grouped_source = Network.of_geometry geometry in
  let grouped_source, inner_value = ok (Network.add_value_node
    Flow.Value_kind.Value grouped_source) in
  let grouped_source, outer_value = ok (Network.add_value_node
    Flow.Value_kind.Value grouped_source) in
  let grouped_source = ok (Network.set_literal
    ~target:(port outer_value "v")
    (Port.Scalar (Param.Float_value 2.)) grouped_source) in
  let grouped_source = ok (Network.connect_value
    ~source:(port outer_value "out") ~target:(port inner_value "v")
    grouped_source) in
  let grouped_source = ok (Network.connect_value
    ~source:(port inner_value "out") ~target:(port selected_id "a")
    grouped_source) in
  let grouped_source = ok (Network.connect_value
    ~source:(port inner_value "out") ~target:(port parent_id "a")
    grouped_source) in
  let grouped, definition, instance = ok (Group.geometry
    ~name:"value_group" ~selected:[selected_id; inner_value]
    ~displayed:(Some selected_id) ~definitions:Network.String_map.empty
    grouped_source) in
  let flat, _ = ok (Compile.flatten
    ~definitions:(Network.String_map.singleton definition.name definition)
    ~compiled_ids:Instance_path.Map.empty grouped) in
  let cooked = ok (Value_lane.resolve (Value_lane.create ()) ~time:0. flat) in
  assert (List.exists (fun (port : Network.interface_port) ->
      port.ty = Flow.Port_type.Float) definition.inputs
    && List.exists (fun (port : Network.interface_port) ->
      port.ty = Flow.Port_type.Float) definition.outputs
    && Network.Int_map.mem instance grouped.instances
    && cook_graph cooked.geometry = cook_graph
      (Procedural.Edit_graph.of_graph (build {default with a = 2.})));
  let ungrouped, mapping, displayed = ok (Group.ungroup
    ~instance_id:instance ~displayed:(Some instance) ~definition grouped) in
  let new_sop = List.assoc selected_id mapping
  and new_value = List.assoc inner_value mapping in
  assert (displayed = Some new_sop
    && new_sop <> selected_id && new_value <> inner_value
    && Port.Map.find (port new_value "v") ungrouped.drives
       = Drive.Wire {node = outer_value; output = "out"}
    && Port.Map.find (port new_sop "a") ungrouped.drives
       = Drive.Wire {node = new_value; output = "out"}
    && Port.Map.find (port parent_id "a") ungrouped.drives
       = Drive.Wire {node = new_value; output = "out"});
  let cooked = ok (Value_lane.resolve (Value_lane.create ())
    ~time:0. ungrouped) in
  assert (cook_graph cooked.geometry = cook_graph
    (Procedural.Edit_graph.of_graph (build {default with a = 2.})));
  let value_only, value_definition, value_instance = ok (Group.geometry
    ~name:"value_only" ~selected:[inner_value]
    ~displayed:(Some selected_id)
    ~definitions:Network.String_map.empty grouped_source) in
  assert (List.length value_definition.inputs = 1
    && List.length value_definition.outputs = 1
    && Network.Int_map.mem value_instance value_only.instances);
  let value_flat, _ = ok (Compile.flatten
    ~definitions:(Network.String_map.singleton value_definition.name
      value_definition) ~compiled_ids:Instance_path.Map.empty value_only) in
  let value_cooked = ok (Value_lane.resolve (Value_lane.create ())
    ~time:0. value_flat) in
  assert (cook_graph value_cooked.geometry = cook_graph
    (Procedural.Edit_graph.of_graph (build {default with a = 2.})));
  let value_ungrouped, value_mapping, _ = ok (Group.ungroup
    ~instance_id:value_instance ~displayed:(Some selected_id)
    ~definition:value_definition value_only) in
  assert (List.length value_mapping = 1
    && Port.Map.find (port selected_id "a") value_ungrouped.drives
       = Drive.Wire {node = List.assoc inner_value value_mapping;
           output = "out"}
    && Port.Map.find (port parent_id "a") value_ungrouped.drives
       = Drive.Wire {node = List.assoc inner_value value_mapping;
           output = "out"});
  let bare, bare_value = ok (Network.add_value_node Flow.Value_kind.Value
    (Network.of_geometry Procedural.Edit_graph.empty)) in
  let bare_grouped, bare_definition, _ = ok (Group.geometry
    ~name:"bare_value" ~selected:[bare_value] ~displayed:None
    ~definitions:Network.String_map.empty bare) in
  let bare_flat, _ = ok (Compile.flatten
    ~definitions:(Network.String_map.singleton bare_definition.name
      bare_definition) ~compiled_ids:Instance_path.Map.empty bare_grouped) in
  assert (Procedural.Edit_graph.root bare_flat.geometry = None);
  let vector_node = build {default with x = 1.; y = 2.; z = 3.} in
  let vector_id = Procedural.Node.id vector_node in
  let vector_graph = Network.of_geometry
    (Procedural.Edit_graph.of_graph vector_node) in
  let vector_graph, vector_source = ok (Network.add_value_node
    Flow.Value_kind.Combine_xyz vector_graph) in
  let vector_graph = ok (Network.connect_value
    ~source:(port vector_source "out")
    ~target:(port vector_id "position") vector_graph) in
  let vector_grouped, vector_definition, vector_instance = ok
    (Group.geometry ~name:"vector_default" ~selected:[vector_id]
      ~displayed:(Some vector_id)
      ~definitions:Network.String_map.empty vector_graph) in
  let vector_port = List.find (fun (port : Network.interface_port) ->
    port.ty = Flow.Port_type.Vec3) vector_definition.inputs in
  assert (vector_port.default = Some (Port.Vector (1., 2., 3.))
    && Port.literal (ok (Network.parameter vector_grouped
       (port vector_instance vector_port.name))) = Port.Vector (1., 2., 3.));
  let vector_grouped = ok (Network.clear_drive
    ~target:(port vector_instance vector_port.name) vector_grouped) in
  let vector_flat, _ = ok (Compile.flatten
    ~definitions:(Network.String_map.singleton vector_definition.name
      vector_definition) ~compiled_ids:Instance_path.Map.empty vector_grouped) in
  let vector_cooked = ok (Value_lane.resolve (Value_lane.create ())
    ~time:0. vector_flat) in
  assert (cook_graph vector_cooked.geometry = cook_graph
    (Procedural.Edit_graph.of_graph vector_node));
  print_endline "Flow SOP overlay: validation, change-only lane, literal restoration and 16,384-point 1/4-domain byte parity pass"
