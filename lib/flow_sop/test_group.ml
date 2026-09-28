open Flow_sop

let ok = function Ok value -> value
  | Error diagnostic -> failwith (Flow.Diagnostic.to_string diagnostic)
let port node path = Port.{node; path}

let positions graph =
  let session = Procedural.Session.create ~max_entries:16
    ~max_payload_bytes:1048576 |> Result.get_ok in
  Fun.protect ~finally:(fun () -> Procedural.Session.close session) (fun () ->
    let graph = Procedural.Edit_graph.compile graph |> Result.get_ok in
    let context = Procedural.Context.create () |> Result.get_ok in
    let output = Procedural.Session.cook session ~context graph |> Result.get_ok in
    let points = Pdk.Geometry.positions output.geometry in
    Array.init (Pdk.Packed.Float3.length points)
      (Pdk.Packed.Float3.get points))

let () =
  let source = Procedural.Sop.points [|1., 2., 3.|] in
  let first = Procedural.Sop.null source in
  let second = Procedural.Sop.null source in
  let consumer = Procedural.Sop.null first in
  let source_id = Procedural.Node.id source
  and first_id = Procedural.Node.id first
  and second_id = Procedural.Node.id second
  and consumer_id = Procedural.Node.id consumer in
  let geometry = Procedural.Edit_graph.of_graph consumer
    |> Procedural.Edit_graph.add_node second |> Result.get_ok in
  let network = Network.of_geometry geometry in
  let grouped, definition, instance = ok (Group.geometry
    ~name:"compound_1" ~selected:[first_id; second_id]
    ~displayed:(Some first_id) ~definitions:Network.String_map.empty network) in
  assert (List.map (fun (port : Network.interface_port) -> port.name)
    definition.inputs = ["in0"]);
  assert (List.map (fun (port : Network.interface_port) -> port.name)
    definition.outputs = ["result"]);
  let definitions = Network.String_map.singleton definition.name definition in
  let interface_id operation = Procedural.Edit_graph.inspect definition.body.geometry
    |> List.find (fun (node : Procedural.Edit_graph.node_info) ->
      node.operation = operation)
    |> fun node -> node.id in
  assert (ok (Network.outputs ~definitions definition.body
    ~node_id:(interface_id "flow_inputs"))
    = ["in0", Flow.Port_type.Geometry]
    && ok (Network.outputs ~definitions definition.body
      ~node_id:(interface_id "flow_outputs")) = []
    && ok (Network.outputs ~definitions grouped ~node_id:instance)
       = ["result", Flow.Port_type.Geometry]);
  assert (Procedural.Edit_graph.find grouped.geometry ~node_id:first_id = None
    && Procedural.Edit_graph.find grouped.geometry ~node_id:second_id = None
    && Procedural.Edit_graph.find definition.body.geometry ~node_id:first_id <> None
    && Procedural.Edit_graph.find definition.body.geometry ~node_id:second_id <> None);
  assert (Network.geometry_source grouped (port instance "in0")
    = Some (port source_id "geo")
    && Network.geometry_source grouped (port consumer_id "in0")
       = Some (port instance "result"));
  let float_port name : Network.interface_port =
    {name; ty = Flow.Port_type.Float; default = Some (Param.Float_value 2.);
     label = String.capitalize_ascii name; soft = Some (0., 10.)} in
  let vec3_port : Network.interface_port =
    {name = "position"; ty = Flow.Port_type.Vec3;
     default = Some (Param.Float_value 1.); label = "Position";
     soft = Some (0., 10.)} in
  let value_definition = {definition with
    inputs = definition.inputs @ [float_port "speed"; vec3_port];
    outputs = definition.outputs @ [float_port "height";
      {vec3_port with name = "position_out"};
      {vec3_port with name = "generated"}]} in
  let factories = Compound_node.factories ~name:value_definition.name
    ~inputs:value_definition.inputs ~outputs:value_definition.outputs in
  let rebind id factory graph = Procedural.Edit_graph.rebind_factory
    ~node_id:id factory graph |> Result.get_ok in
  let value_body = definition.body.geometry
    |> rebind (interface_id "flow_inputs") (List.nth factories 0)
    |> rebind (interface_id "flow_outputs") (List.nth factories 1)
    |> fun geometry -> ok (Network.with_geometry geometry definition.body) in
  let value_body, value_id = ok (Network.add_value_node Flow.Value_kind.Value value_body) in
  let value_body = ok (Network.connect_value
    ~source:(port (interface_id "flow_inputs") "speed")
    ~target:(port value_id "v") value_body) in
  let value_body = ok (Network.connect_value
    ~source:(port value_id "out")
    ~target:(port (interface_id "flow_outputs") "height") value_body) in
  let value_body = ok (Network.connect_value
    ~source:(port (interface_id "flow_inputs") "position")
    ~target:(port (interface_id "flow_outputs") "position_out") value_body) in
  let value_body, generated = ok (Network.add_value_node
    Flow.Value_kind.Combine_xyz value_body) in
  let value_body = ok (Network.set_literal ~target:(port generated "x")
    (Port.Scalar (Param.Float_value 9.)) value_body) in
  let value_body = ok (Network.connect_value
    ~source:(port generated "out")
    ~target:(port (interface_id "flow_outputs") "generated") value_body) in
  let value_grouped = grouped.geometry
    |> rebind instance (List.nth factories 2)
    |> fun geometry -> ok (Network.with_geometry geometry grouped) in
  let value_grouped = ok (Network.set_literal ~target:(port instance "speed")
    (Port.Scalar (Param.Float_value 4.)) value_grouped) in
  let value_grouped = ok (Network.set_literal ~target:(port instance "position")
    (Port.Vector (3., 4., 5.)) value_grouped) in
  let value_grouped, outside_id = ok (Network.add_value_node
    Flow.Value_kind.Value value_grouped) in
  let value_grouped = ok (Network.connect_value
    ~source:(port instance "height") ~target:(port outside_id "v")
    value_grouped) in
  let value_grouped, position_driver = ok (Network.add_value_node
    Flow.Value_kind.Value value_grouped) in
  let value_grouped = ok (Network.set_literal
    ~target:(port position_driver "v")
    (Port.Scalar (Param.Float_value 7.)) value_grouped) in
  let value_grouped = ok (Network.connect_value
    ~source:(port position_driver "out")
    ~target:(port instance "position.x") value_grouped) in
  let value_grouped, position_sink = ok (Network.add_value_node
    Flow.Value_kind.Value value_grouped) in
  let value_grouped = ok (Network.connect_value
    ~source:(port instance "position_out.y")
    ~target:(port position_sink "v") value_grouped) in
  let value_grouped, generated_sink = ok (Network.add_value_node
    Flow.Value_kind.Value value_grouped) in
  let value_grouped = ok (Network.connect_value
    ~source:(port instance "generated.x")
    ~target:(port generated_sink "v") value_grouped) in
  assert (match Network.set_literal ~target:(port instance "speed")
      (Port.Scalar (Param.Float_value nan)) value_grouped with
    | Error diagnostic -> diagnostic.Flow.Diagnostic.code = "E_TYPE"
    | Ok _ -> false);
  let invalid_instance = {Network.definition = value_definition.name;
    literals = Network.String_map.singleton "speed" (Param.Text_value "bad")} in
  assert (match Network.of_parts ~geometry:value_grouped.geometry
      ~values:value_grouped.values ~drives:value_grouped.drives
      ~geometry_outputs:value_grouped.geometry_outputs
      ~instances:(Network.Int_map.add instance invalid_instance
        value_grouped.instances) with
    | Error diagnostic -> diagnostic.Flow.Diagnostic.code = "E_TYPE"
    | Ok _ -> false);
  assert (Network.output_type value_body
      (port (interface_id "flow_inputs") "speed") = Ok Flow.Port_type.Float
    && Network.output_type value_grouped (port instance "height")
       = Ok Flow.Port_type.Float
    && Result.is_ok (Network.topological_values value_body)
    && Result.is_ok (Network.topological_values value_grouped)
    && Port.literal (ok (Network.parameter value_grouped
       (port instance "speed"))) = Port.Scalar (Param.Float_value 4.)
    && Port.literal (ok (Network.parameter value_grouped
       (port instance "position"))) = Port.Vector (3., 4., 5.)
    && Network.String_map.find "speed"
       (Network.Int_map.find instance value_grouped.instances).literals
       = Param.Float_value 4.);
  let value_definition = {value_definition with body = value_body} in
  let ungrouped_value, value_mapping, _ = ok (Group.ungroup
    ~instance_id:instance ~displayed:(Some instance)
    ~definition:value_definition value_grouped) in
  let cloned_value = List.assoc value_id value_mapping in
  let resolved = ok (Value_lane.resolve (Value_lane.create ())
    ~time:0. ungrouped_value) in
  assert (Port.literal (ok (Network.parameter ungrouped_value
      (port cloned_value "v"))) = Port.Scalar (Param.Float_value 4.)
    && Port.Map.find (port outside_id "v") ungrouped_value.drives
       = Drive.Wire {node = cloned_value; output = "out"}
    && Port.literal (ok (Network.parameter ungrouped_value
       (port position_sink "v"))) = Port.Scalar (Param.Float_value 4.)
    && Port.Map.find (port generated_sink "v") resolved.applied
       = Flow.Port_type.Float_value 9.);
  let flat, ids = ok (Compile.flatten
    ~definitions:(Network.String_map.singleton definition.name definition)
    ~compiled_ids:Instance_path.Map.empty grouped) in
  assert (Instance_path.Map.mem [instance; first_id] ids
    && positions flat.geometry = positions
      (Procedural.Edit_graph.of_graph first));
  assert (Procedural.Edit_graph.root grouped.geometry = Some instance);
  let ungrouped, mapping, displayed = ok (Group.ungroup
    ~instance_id:instance ~displayed:(Some instance) ~definition grouped) in
  let cloned_first = List.assoc first_id mapping
  and cloned_second = List.assoc second_id mapping in
  assert (cloned_first <> first_id && cloned_second <> second_id
    && displayed = Some cloned_first
    && Network.geometry_source ungrouped (port cloned_first "in0")
       = Some (port source_id "geo")
    && Network.geometry_source ungrouped (port cloned_second "in0")
       = Some (port source_id "geo")
    && Network.geometry_source ungrouped (port consumer_id "in0")
       = Some (port cloned_first "geo")
    && positions ungrouped.geometry = positions
      (Procedural.Edit_graph.of_graph first));
  let other_consumer = Procedural.Sop.null second in
  let other_id = Procedural.Node.id other_consumer in
  let two_outputs = Procedural.Edit_graph.add_node other_consumer geometry
    |> Result.get_ok |> Network.of_geometry in
  let grouped, definition, instance = ok (Group.geometry
    ~name:"compound_2" ~selected:[first_id; second_id]
    ~displayed:(Some first_id) ~definitions:Network.String_map.empty
    two_outputs) in
  assert (List.map (fun (port : Network.interface_port) -> port.name)
    definition.outputs = ["result"; "result_2"]
    && Network.geometry_source grouped (port consumer_id "in0")
       = Some (port instance "result")
    && Network.geometry_source grouped (port other_id "in0")
       = Some (port instance "result_2"));
  let flat, _ = ok (Compile.flatten
    ~definitions:(Network.String_map.singleton definition.name definition)
    ~compiled_ids:Instance_path.Map.empty grouped) in
  assert (positions flat.geometry = positions
    (Procedural.Edit_graph.of_graph first));
  let ungrouped, mapping, _ = ok (Group.ungroup
    ~instance_id:instance ~displayed:(Some instance) ~definition grouped) in
  assert (Network.geometry_source ungrouped (port other_id "in0")
    = Some (port (List.assoc second_id mapping) "geo"));
  assert (match Group.geometry ~name:"compound_1" ~selected:[]
      ~displayed:None ~definitions:Network.String_map.empty network with
    | Error diagnostic -> diagnostic.Flow.Diagnostic.code = "E_GROUP"
    | Ok _ -> false);
  print_endline "Flow compound grouping: geometry boundary, identity and cook parity pass"
