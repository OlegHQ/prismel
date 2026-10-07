module Int_map = Map.Make (Int)
module Int_set = Set.Make (Int)
type t = { geometry : Procedural.Edit_graph.t; drives : Flow.Eval.value Port.Map.t; states : Flow.Eval.value list;
  frame_nodes : (Flow.Eval.state -> Procedural.Node.t -> Procedural.Node.t) Int_map.t }
let error code message = Error (Flow.Diagnostic.error ~code message)
let geometry_error result = Result.map_error (Flow.Diagnostic.error ~code:"E_GEOMETRY") result
let of_geometry geometry = {geometry; drives = Port.Map.empty; states = []; frame_nodes = Int_map.empty}
let with_states states network = {network with states}
let with_frame_nodes frame_nodes network = {network with frame_nodes}
let fields network ~node_id = match Procedural.Edit_graph.find network.geometry ~node_id with
  | Some node ->
      let fields = Procedural.Node.parameter_fields node in
      if fields <> [] then Ok fields
      else Ok (Procedural.Edit_graph.node_factory_fields network.geometry ~node_id)
  | None -> error "E_UNBOUND" (Printf.sprintf "No node %d" node_id)
let parameters network ~node_id = Result.bind (fields network ~node_id) Port.parameters
let parameter network (port : Port.t) = Result.bind (parameters network ~node_id:port.node)
  (fun parameters -> Port.find_parameter parameters port.path)

(* a slot and a parameter never share a name; every drive targets a parameter of a node *)
let validate_node network node_id =
  Result.bind (parameters network ~node_id) (fun parameters ->
    let slots = Option.value (Procedural.Edit_graph.node_slot_names network.geometry
      ~node_id) ~default:[] in
    if List.exists (fun parameter -> List.mem parameter.Port.path slots) parameters then
      error "E_PORT" "A slot and parameter have the same name" else Ok ())
let validate network =
  let checked = List.fold_left (fun checked (node : Procedural.Edit_graph.node_info) ->
    Result.bind checked (fun () -> validate_node network node.id))
    (Ok ()) (Procedural.Edit_graph.inspect network.geometry) in
  Result.bind checked (fun () ->
    Port.Map.fold (fun target _ checked -> Result.bind checked (fun () ->
      Result.map (fun _ -> ()) (parameter network target))) network.drives (Ok ()))
let with_drives drives network =
  let next = {network with drives} in
  Result.map (fun () -> next) (validate next)
let with_geometry geometry network =
  if geometry == network.geometry then Ok network else
    let next = {network with geometry} in
    Result.map (fun () -> next) (validate next)
let apply_parameters ~node_id changes network =
  Result.bind (Result.map_error (Flow.Diagnostic.error ~code:"E_TYPE")
      (Procedural.Edit_graph.apply_parameters network.geometry ~node_id changes)) (fun (geometry, _) ->
    if geometry == network.geometry then Ok network else
    let next = {network with geometry} in
    Result.bind (validate_node next node_id) (fun () ->
      Port.Map.fold (fun (port : Port.t) _ result -> if port.node <> node_id then result else
          Result.bind result (fun () -> Result.map (fun _ -> ()) (parameter next port)))
        next.drives (Ok ()) |> Result.map (fun () -> next)))
let relabel ~node_id label network =
  if String.trim label = "" then Ok network else
  match Procedural.Edit_graph.find network.geometry ~node_id with
  | None -> error "E_UNBOUND" (Printf.sprintf "No node %d" node_id)
  | Some node -> Result.map (fun geometry -> if geometry == network.geometry then network
      else {network with geometry})
      (geometry_error (Procedural.Edit_graph.replace_node
        (Procedural.Node.relabel label node) network.geometry))
let remove_nodes ids network =
  let removed = Int_set.of_list ids in
  let geometry_ids = List.filter (fun id -> Procedural.Edit_graph.find network.geometry ~node_id:id <> None) ids in
  if geometry_ids = [] then Ok network else
    Ok {network with geometry = Procedural.Edit_graph.remove_nodes geometry_ids network.geometry;
        frame_nodes = Int_map.filter (fun id _ -> not (Int_set.mem id removed)) network.frame_nodes;
        drives = Port.Map.filter (fun (target : Port.t) _ -> not (Int_set.mem target.node removed)) network.drives}
