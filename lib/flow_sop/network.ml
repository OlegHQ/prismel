module Int_map = Map.Make (Int)
module Int_set = Set.Make (Int)
type t = { geometry : Procedural.Edit_graph.t; values : Flow.Graph.t; drives : Drive.t Port.Map.t }
type fragment = {
  geometry_fragment : Procedural.Edit_graph.fragment option;
  value_nodes : Flow.Graph.node list;
  fragment_drives : Drive.t Port.Map.t;
}
let error code message = Error (Flow.Diagnostic.error ~code message)
let geometry_error result = Result.map_error (Flow.Diagnostic.error ~code:"E_GEOMETRY") result
let of_geometry geometry = {geometry; values = Flow.Graph.empty; drives = Port.Map.empty}
let fields network ~node_id = match Flow.Graph.find network.values ~node_id with
  | Some node -> Ok (Flow.Value_kind.fields node.parameters)
  | None -> match Procedural.Edit_graph.find network.geometry ~node_id with
      | Some node -> Ok (Procedural.Node.parameter_fields node)
      | None -> error "E_UNBOUND" (Printf.sprintf "No node %d" node_id)
let parameters network ~node_id = Result.bind (fields network ~node_id) Port.parameters
let parameter network (port : Port.t) = Result.bind (parameters network ~node_id:port.node)
  (fun parameters -> Port.find_parameter parameters port.path)
let output_type network (port : Port.t) = match Flow.Graph.find network.values ~node_id:port.node with
  | Some node -> (match List.assoc_opt port.path (Flow.Graph.outputs node) with
      | Some ty -> Ok ty | None -> error "E_PORT" ("No value output " ^ port.path))
  | None -> match Procedural.Edit_graph.find network.geometry ~node_id:port.node with
      | Some _ when port.path = "geo" -> Ok Flow.Port_type.Geometry
      | Some _ -> error "E_PORT" ("No geometry output " ^ port.path)
      | None -> error "E_UNBOUND" (Printf.sprintf "No source node %d" port.node)

type visit = Enter of int | Leave of int
let topological_values network =
  let nodes = Flow.Graph.inspect network.values in
  let dependencies = Port.Map.fold (fun (target : Port.t) drive dependencies -> match drive with
    | Drive.Wire source when Flow.Graph.find network.values ~node_id:target.node <> None ->
        Int_map.update target.node (fun current -> Some (source.node :: Option.value current ~default:[])) dependencies
    | _ -> dependencies) network.drives Int_map.empty in
  let colors = Hashtbl.create (List.length nodes) in
  let rec walk result = function
    | [] -> Ok (List.rev result)
    | Leave id :: rest -> Hashtbl.replace colors id 2; walk (id :: result) rest
    | Enter id :: rest -> match Hashtbl.find_opt colors id with
        | Some 2 -> walk result rest
        | Some 1 -> error "E_CYCLE" (Printf.sprintf "Value cycle through node %d" id)
        | _ ->
            if Flow.Graph.find network.values ~node_id:id = None then
              error "E_UNBOUND" (Printf.sprintf "No value source node %d" id)
            else begin
              Hashtbl.replace colors id 1;
              let next = List.fold_left (fun next id -> Enter id :: next)
                (Leave id :: rest) (Option.value (Int_map.find_opt id dependencies) ~default:[]) in
              walk result next
            end in
  walk [] (List.map (fun (node : Flow.Graph.node) -> Enter node.id) nodes)

let validate_drive network (target : Port.t) drive =
  Result.bind (parameter network target) (fun parameter -> match parameter.Port.ty with
    | None -> error "E_TYPE" ("Port " ^ target.path ^ " is literal-only")
    | Some target_type ->
        let source_type = match drive with Drive.Expr _ -> Ok Flow.Port_type.Float
          | Drive.Wire source -> output_type network {node = source.node; path = source.output} in
        Result.bind source_type (fun source_type ->
          if not (Flow.Port_type.can_connect ~source:source_type ~target:target_type) then
            error "E_TYPE" (Printf.sprintf "Cannot drive %s with %s"
              (Flow.Port_type.name target_type) (Flow.Port_type.name source_type))
          else
            let conflict = match parameter.fields with
              | [field] -> (match field.Param.vec3 with
                  | Some (group, _) -> Port.Map.mem {target with path = group} network.drives
                  | None -> false)
              | _ -> List.exists (fun component ->
                  Port.Map.mem {target with path = component.Port.path} network.drives) (Port.components parameter) in
            if conflict then error "E_VEC3_CONFLICT" ("Clear the other drive on " ^ target.path ^ " first") else Ok ()))
let validate network =
  let value_nodes = Flow.Graph.inspect network.values in
  let collision = List.find_opt (fun (node : Flow.Graph.node) ->
    Procedural.Edit_graph.find network.geometry ~node_id:node.id <> None) value_nodes in
  match collision with
  | Some node -> error "E_DUPLICATE" (Printf.sprintf "Node %d is both SOP and value" node.id)
  | None ->
      let nodes = List.map (fun (node : Flow.Graph.node) -> node.id) value_nodes
        @ List.map (fun (node : Procedural.Edit_graph.node_info) -> node.id) (Procedural.Edit_graph.inspect network.geometry) in
      let checked = List.fold_left (fun checked id -> Result.bind checked (fun () ->
        Result.bind (parameters network ~node_id:id) (fun parameters ->
          let slots = Option.value (Procedural.Edit_graph.node_slot_names network.geometry ~node_id:id) ~default:[] in
          if List.exists (fun parameter -> List.mem parameter.Port.path slots) parameters then
            error "E_PORT" "A slot and parameter have the same name" else Ok ()))) (Ok ()) nodes in
      Result.bind checked (fun () -> Result.bind
        (Port.Map.fold (fun target drive checked -> Result.bind checked (fun () -> validate_drive network target drive))
          network.drives (Ok ())) (fun () -> Result.map (fun _ -> ()) (topological_values network)))
let of_parts ~geometry ~values ~drives =
  let network = {geometry; values; drives} in
  Result.bind (validate network) (fun () ->
    Result.map (fun () -> network) (List.fold_left (fun checked (node : Flow.Graph.node) ->
      Result.bind checked (fun () -> geometry_error (Procedural.Node.Private.reserve_id node.id)))
      (Ok ()) (Flow.Graph.inspect values)))
let with_geometry geometry network =
  if geometry == network.geometry then Ok network else
    let next = {network with geometry} in Result.map (fun () -> next) (validate next)
let relabel ~node_id label network =
  if String.trim label = "" then Ok network else
  match Flow.Graph.find network.values ~node_id with
  | Some _ -> Result.map (fun values -> if values == network.values then network
      else {network with values})
      (Flow.Graph.relabel network.values ~node_id label)
  | None -> match Procedural.Edit_graph.find network.geometry ~node_id with
    | None -> error "E_UNBOUND" (Printf.sprintf "No node %d" node_id)
    | Some node -> Result.map (fun geometry -> if geometry == network.geometry then network
        else {network with geometry})
        (geometry_error (Procedural.Edit_graph.replace_node
          (Procedural.Node.relabel label node) network.geometry))
let add_value_node ?label kind network =
  let id = Procedural.Node.Private.fresh_id () in
  Result.bind (Flow.Graph.node ~id ?label kind) (fun node ->
    Result.map (fun values -> {network with values}, id) (Flow.Graph.add_node node network.values))
let remove_nodes ids network =
  let removed = Int_set.of_list ids in
  let geometry_ids = List.filter (fun id -> Procedural.Edit_graph.find network.geometry ~node_id:id <> None) ids in
  let value_ids = List.filter (fun id -> Flow.Graph.find network.values ~node_id:id <> None) ids in
  if geometry_ids = [] && value_ids = [] then Ok network else
    let geometry = if geometry_ids = [] then network.geometry else Procedural.Edit_graph.remove_nodes geometry_ids network.geometry in
    let values = Flow.Graph.remove_nodes value_ids network.values in
    let drives = Port.Map.filter (fun (target : Port.t) drive -> not (Int_set.mem target.node removed)
      && match drive with Drive.Expr _ -> true | Drive.Wire source -> not (Int_set.mem source.node removed)) network.drives in
    Ok {geometry; values; drives}
let set_drive ~target drive network =
  if Port.Map.find_opt target network.drives = Some drive then Ok network else
    let next = {network with drives = Port.Map.add target drive network.drives} in
    Result.map (fun () -> next) (validate next)
let connect_value ~(source : Port.t) ~target network =
  set_drive ~target (Drive.Wire {node = source.node; output = source.path}) network
let set_expr ~target expression network = set_drive ~target (Drive.Expr expression) network
let clear_drive ~target network = Result.map (fun _ ->
  if Port.Map.mem target network.drives then {network with drives = Port.Map.remove target network.drives} else network)
  (parameter network target)
let disconnect ~(target : Port.t) network =
  let slots = Option.value (Procedural.Edit_graph.node_slot_names network.geometry ~node_id:target.node) ~default:[] in
  let rec index i = function [] -> None | name :: rest -> if name = target.path then Some i else index (i+1) rest in
  match index 0 slots with
  | None -> clear_drive ~target network
  | Some input_index -> Result.bind (geometry_error (Procedural.Edit_graph.disconnect
      ~consumer:target.node ~input_index network.geometry)) (fun geometry -> with_geometry geometry network)
let set_literal ~(target : Port.t) value network =
  Result.bind (parameter network target) (fun parameter -> Result.bind (Port.literal_changes parameter value) (fun changes ->
    match Flow.Graph.find network.values ~node_id:target.node with
    | Some _ -> Result.map (fun (values, _) -> if values == network.values then network else {network with values})
        (Flow.Graph.apply_parameters network.values ~node_id:target.node changes)
    | None -> Result.bind (Result.map_error (Flow.Diagnostic.error ~code:"E_TYPE")
        (Procedural.Edit_graph.apply_parameters network.geometry ~node_id:target.node changes))
        (fun (geometry, _) -> with_geometry geometry network)))

let apply_value_parameters network ~node_id changes =
  Result.map (fun (values, effects) ->
    (if values == network.values then network else {network with values}), effects)
    (Flow.Graph.apply_parameters network.values ~node_id changes)

let copy_nodes ids network =
  if ids = [] then error "E_SELECTION" "Select nodes to copy" else
    let selected = Int_set.of_list ids in
    let known = List.fold_left (fun checked id -> Result.bind checked (fun () ->
      Result.map (fun _ -> ()) (fields network ~node_id:id))) (Ok ()) ids in
    Result.bind known (fun () ->
      let geometry_ids = List.filter (fun id -> Procedural.Edit_graph.find network.geometry ~node_id:id <> None) ids in
      let geometry_fragment = if geometry_ids = [] then Ok None else
        Result.map Option.some (geometry_error (Procedural.Edit_graph.copy_nodes geometry_ids network.geometry)) in
      Result.map (fun geometry_fragment ->
        let value_nodes = List.filter (fun (node : Flow.Graph.node) -> Int_set.mem node.id selected)
          (Flow.Graph.inspect network.values) in
        let fragment_drives = Port.Map.filter (fun (target : Port.t) drive -> Int_set.mem target.node selected
          && match drive with Drive.Expr _ -> true | Drive.Wire source -> Int_set.mem source.node selected) network.drives in
        {geometry_fragment; value_nodes; fragment_drives}) geometry_fragment)
let paste fragment network =
  let geometry = match fragment.geometry_fragment with
    | None -> Ok (network.geometry, [])
    | Some fragment -> geometry_error (Procedural.Edit_graph.paste fragment network.geometry) in
  Result.bind geometry (fun (geometry, geometry_mapping) ->
    let values = List.fold_left (fun checked (source : Flow.Graph.node) ->
      Result.bind checked (fun (values, mapping) ->
        let id = Procedural.Node.Private.fresh_id () in
        Result.bind (Flow.Graph.clone_node ~id source) (fun node ->
          Result.map (fun values -> values, (source.id,id) :: mapping) (Flow.Graph.add_node node values))))
      (Ok (network.values, geometry_mapping)) fragment.value_nodes in
    Result.bind values (fun (values, mapping) ->
      let remap = List.fold_left (fun remap (old_id, new_id) -> Int_map.add old_id new_id remap) Int_map.empty mapping in
      let drives = Port.Map.fold (fun (target : Port.t) drive drives ->
        let drive = match drive with Drive.Expr _ -> drive | Drive.Wire source ->
          Drive.Wire {source with node = Int_map.find source.node remap} in
        Port.Map.add {target with node = Int_map.find target.node remap} drive drives)
        fragment.fragment_drives network.drives in
      let next = {geometry; values; drives} in
      Result.map (fun () -> next, List.sort (fun (a,_) (b,_) -> Int.compare a b) mapping) (validate next)))
