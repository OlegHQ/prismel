open Flow_sop
let ok = function Ok value -> value | Error diagnostic -> failwith (Flow.Diagnostic.to_string diagnostic)
let rejected code = function
  | Ok _ -> failwith ("Expected " ^ code)
  | Error diagnostic -> assert (diagnostic.Flow.Diagnostic.code = code)

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
  let cook graph =
    let session = Procedural.Session.create ~max_entries:16
      ~max_payload_bytes:1048576 |> Result.get_ok in
    Fun.protect ~finally:(fun () -> Procedural.Session.close session) (fun () ->
      let context = Procedural.Context.create () |> Result.get_ok in
      let graph = Procedural.Edit_graph.compile graph |> Result.get_ok in
      let result = Procedural.Session.cook session ~context graph |> Result.get_ok in
      geometry_bytes result.geometry) in
  assert (cook compiled.geometry = cook
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
    && cook compiled.geometry = cook
      (Procedural.Edit_graph.of_graph (Procedural.Sop.null source)));
  let network, time = ok (Network.add_value_node Flow.Value_kind.Time base) in
  assert (time <> id);
  let network, vector = ok (Network.add_value_node Flow.Value_kind.Combine_xyz network) in
  let network, math = ok (Network.add_value_node Flow.Value_kind.Math network) in
  let network = ok (Network.connect_value ~source:(port time "t") ~target:(port math "a") network) in
  let network = ok (Network.connect_value ~source:(port math "out") ~target:(port id "a") network) in
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
  rejected "E_VEC3_CONFLICT" (Network.connect_value ~source:(port vector "out") ~target:(port id "position") component);
  let literal = ok (Network.set_literal ~target:(port id "position") (Port.Vector (1.,2.,3.)) network) in
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
  print_endline "Flow SOP overlay: validation, change-only lane, literal restoration and 16,384-point 1/4-domain byte parity pass"
