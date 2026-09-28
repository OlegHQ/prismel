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
