type argument = Input of int | Node of int
type node = { id:int; name:string; arguments:argument array; dependencies:int array }
type graph = { function_name:string; nodes:node array; output:int option; attributes:string array }
type owned = { token:int; device:int; destroyed:bool }
type descriptor = { device:int; functions:owned array; archives:owned array; graphs:graph array; options:int64 }

let snapshot_node node = { node with arguments=Array.copy node.arguments; dependencies=Array.copy node.dependencies }

let validate_graph ~argument_count ~function_name ~nodes ~output ~attributes =
  if argument_count < 0 || function_name = "" then Error "invalid stitching graph identity"
  else
    let nodes = Array.map snapshot_node nodes and attributes = Array.copy attributes in
    let ids = Hashtbl.create (Array.length nodes) in
    let valid = ref true in
    Array.iter (fun node -> if node.id < 0 || node.name = "" || Hashtbl.mem ids node.id then valid:=false else Hashtbl.add ids node.id node) nodes;
    if not !valid then Error "invalid or duplicate stitching node"
    else if (match output with Some id -> not (Hashtbl.mem ids id) | None -> false) then Error "stitching output is not a graph member"
    else
      let edge_ok = function Input index -> index >= 0 && index < argument_count | Node id -> Hashtbl.mem ids id in
      if Array.exists (fun node -> not (Array.for_all edge_ok node.arguments) || not (Array.for_all (Hashtbl.mem ids) node.dependencies)) nodes
      then Error "stitching edge is not a graph member"
      else
        let state = Hashtbl.create (Array.length nodes) in
        let rec visit id =
          match Hashtbl.find_opt state id with Some 1 -> false | Some 2 -> true | _ ->
            Hashtbl.replace state id 1;
            let node = Hashtbl.find ids id in
            let edges = Array.to_list node.dependencies @ (node.arguments |> Array.to_list |> List.filter_map (function Node id->Some id|Input _->None)) in
            let ok = List.for_all visit edges in Hashtbl.replace state id 2; ok
        in
        if not (Array.for_all (fun node -> visit node.id) nodes) then Error "stitching graph contains a cycle"
        else Ok {function_name;nodes;output;attributes}

let validate_owned ~device values =
  let values=Array.copy values in
  if Array.exists (fun (value : owned) -> value.destroyed) values then Error "destroyed stitched descriptor object"
  else if Array.exists (fun (value : owned) -> value.device<>device) values then Error "stitched descriptor object belongs to another device"
  else Ok values

let create_descriptor ~device ~functions ~archives ~graphs ~options =
  match validate_owned ~device functions, validate_owned ~device archives with
  | Error error,_|_,Error error->Error error
  | Ok functions,Ok archives->Ok {device;functions;archives;graphs=Array.copy graphs;options}

let replace_graphs descriptor graphs = {descriptor with graphs=Array.copy graphs}

let validate_handoff () =
  if List.length Binding_function_stitching_handoff.callable_ids<>36 then invalid_arg "FunctionStitching callable36 drift"
