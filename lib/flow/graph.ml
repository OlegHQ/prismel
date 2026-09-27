type node = { id : int; label : string; parameters : Value_kind.t }
module Int_map = Map.Make (Int)
type t = node Int_map.t

let node ~id ?label kind =
  if id < 1 || id = max_int then
    Error (Diagnostic.error ~code:"E_NODE_ID" "Node id must be positive and below max_int")
  else Ok {id; label = Option.value label ~default:(Value_kind.label kind); parameters = Value_kind.make kind}
let clone_node ~id node =
  if id < 1 || id = max_int then
    Error (Diagnostic.error ~code:"E_NODE_ID" "Node id must be positive and below max_int")
  else Ok {node with id}
let empty = Int_map.empty
let find graph ~node_id = Int_map.find_opt node_id graph
let inspect graph = Int_map.bindings graph |> List.map snd
let add_node node graph =
  if Int_map.mem node.id graph then Error (Diagnostic.error ~code:"E_DUPLICATE"
    (Printf.sprintf "Node %d already exists" node.id))
  else Ok (Int_map.add node.id node graph)
let remove_nodes ids graph = List.fold_left (fun graph id -> Int_map.remove id graph) graph ids
let update graph ~node_id change = match find graph ~node_id with
  | None -> Error (Diagnostic.error ~code:"E_UNBOUND" (Printf.sprintf "No value node %d" node_id))
  | Some node -> Result.map (fun next -> if next == node then graph else Int_map.add node_id next graph) (change node)
let relabel graph ~node_id label = update graph ~node_id (fun node ->
  Ok (if node.label = label then node else {node with label}))
let apply_parameters graph ~node_id changes = match find graph ~node_id with
  | None -> Error (Diagnostic.error ~code:"E_UNBOUND" (Printf.sprintf "No value node %d" node_id))
  | Some node -> Result.map (fun (parameters, effects) ->
      (if parameters == node.parameters then graph else Int_map.add node_id {node with parameters} graph), effects)
      (Value_kind.apply_parameters node.parameters changes)
let outputs node = Value_kind.outputs (Value_kind.kind node.parameters)
