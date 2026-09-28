let geometry_names ports = List.filter_map (fun (port : Network.interface_port) ->
  if port.ty = Flow.Port_type.Geometry then Some port.name else None) ports

let key ~name = function
  | `Inputs -> "flow.inputs:" ^ name
  | `Outputs -> "flow.outputs:" ^ name
  | `Instance -> "flow.instance:" ^ name

let factory ~name ~role ~operation ~label slots =
  let key = key ~name role in
  let build inputs = Procedural.Node.Private.make ~label ~operation
    ~version:1 ~parameters:name ~cook_mode:Procedural.Node.Generic
    ~dependencies:Procedural.Context.Dependencies.static
    ~inputs:(List.filter_map Fun.id inputs |> Array.of_list)
    (fun ~node_id:_ _ _ -> Error (Procedural.Diagnostic.error
      ~code:"E_INTERFACE" "Compound interfaces must be flattened before cooking")) in
  match slots with
  | [] -> Procedural.Edit_graph.factory ~key ~operation ~label
      ~category:["Flow"] ~arity:0 (fun _ -> build [])
  | slots -> Procedural.Edit_graph.factory_slots ~key ~operation ~label
      ~category:["Flow"] ~slots
      ~inputs:(List.map (fun _ -> Procedural.Edit_graph.Optional) slots) build

let factories ~name ~inputs ~outputs = [
  factory ~name ~role:`Inputs ~operation:"flow_inputs" ~label:"Inputs" [];
  factory ~name ~role:`Outputs ~operation:"flow_outputs" ~label:"Outputs"
    (geometry_names outputs);
  factory ~name ~role:`Instance ~operation:"flow_compound" ~label:name
    (geometry_names inputs);
]
