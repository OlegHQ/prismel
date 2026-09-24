module Id_map = Map.Make (Int)
module Id_set = Set.Make (Int)

type connection = {
  source : int;
  consumer : int;
  input_index : int;
}

type input_requirement = Required | Optional

type factory = {
  key : string;
  operation : string;
  label : string;
  category : string list;
  requirements : input_requirement array;
  build : Node.t option list -> Node.t;
}

type entry = {
  node : Node.t;
  inputs : int option array;
  factory : factory option;
}

type t = {
  entries : entry Id_map.t;
  order_rev : int list;
  root : int option;
}

type fragment = {
  fragment_entries : (int * entry) list;
  fragment_root : int option;
}

type node_info = {
  node : Node.t;
  id : int;
  label : string;
  operation : string;
  version : int;
  parameters : string;
  cook_mode : Node.cook_mode;
  dependencies : Context.Dependencies.t;
  inputs : int option array;
  has_parameters : bool;
}

let of_graph graph =
  let infos = Graph.inspect graph in
  let entries = infos |> List.fold_left (fun entries info ->
    let node = Option.get (Graph.find graph ~node_id:info.Graph.id) in
    let inputs = Array.of_list (List.map Option.some info.input_ids) in
    Id_map.add info.id { node; inputs; factory = None } entries) Id_map.empty in
  { entries; order_rev = List.rev_map (fun info -> info.Graph.id) infos;
    root = Some (Node.id graph) }

let root value = value.root

let set_root node_id value =
  if Id_map.mem node_id value.entries then Ok { value with root = Some node_id }
  else Error (Printf.sprintf "editable graph has no node #%d" node_id)

let info (entry : entry) : node_info =
  let node = entry.node in
  { node; id = Node.id node; label = Node.label node;
    operation = Node.operation node; version = Node.version node;
    parameters = Node.parameters node; cook_mode = Node.cook_mode node;
    dependencies = Node.dependencies node; inputs = Array.copy entry.inputs;
    has_parameters = Node.has_parameters node }

let inspect value = List.filter_map (fun id ->
  Option.map info (Id_map.find_opt id value.entries)) (List.rev value.order_rev)

let find value ~node_id = Option.map (fun (entry : entry) -> entry.node)
    (Id_map.find_opt node_id value.entries)

let inputs value ~node_id = Option.map (fun (entry : entry) ->
    Array.copy entry.inputs)
    (Id_map.find_opt node_id value.entries)

let connections value =
  inspect value |> List.fold_left (fun result node ->
    let result = ref result in
    Array.iteri (fun input_index -> function
      | None -> ()
      | Some source -> result :=
          { source; consumer = node.id; input_index } :: !result) node.inputs;
    !result) [] |> List.rev

let compile_node value ~node_id =
  let visiting = Hashtbl.create (Id_map.cardinal value.entries)
  and compiled = Hashtbl.create (Id_map.cardinal value.entries) in
  let rec build id =
    match Hashtbl.find_opt compiled id with
    | Some node -> Ok node
    | None when Hashtbl.mem visiting id ->
        Error (Printf.sprintf "editable graph contains a cycle through node #%d" id)
    | None ->
        (match Id_map.find_opt id value.entries with
         | None -> Error (Printf.sprintf "editable graph references missing node #%d" id)
         | Some (entry : entry) ->
             Hashtbl.add visiting id ();
             let compiled_inputs = Array.make (Array.length entry.inputs) None in
             let rec build_inputs index =
               if index = Array.length entry.inputs then Ok ()
               else match entry.inputs.(index) with
                 | None ->
                     let optional = match entry.factory with
                       | Some factory ->
                           factory.requirements.(index) = Optional
                       | None -> false in
                     if optional then build_inputs (index + 1)
                     else Error (Printf.sprintf
                       "node %S input %d is disconnected"
                       (Node.label entry.node) index)
                 | Some input_id ->
                     Result.bind (build input_id) (fun input ->
                       compiled_inputs.(index) <- Some input;
                       build_inputs (index + 1))
             in
             let result = Result.bind (build_inputs 0) (fun () ->
               let rebuild () = match entry.factory with
                 | Some factory when Array.exists (( = ) Optional)
                       factory.requirements ->
                     let node = factory.build (Array.to_list compiled_inputs) in
                     let changes = Node.parameter_fields entry.node
                         |> List.map (fun field ->
                           field.Parameter.name, field.current) in
                     Result.map (fun (node, _) ->
                       Node.Private.adopt_identity ~source:entry.node node)
                       (Node.apply_parameters node changes)
                 | _ ->
                     let inputs = Array.map Option.get compiled_inputs in
                     Ok (Node.Private.rebuild_with_inputs entry.node inputs) in
               Result.map (fun node ->
               Hashtbl.remove visiting id;
               Hashtbl.add compiled id node;
               node) (rebuild ())) in
             if Result.is_error result then Hashtbl.remove visiting id;
             result)
  in
  if not (Id_map.mem node_id value.entries) then
    Error (Printf.sprintf "editable graph has no node #%d" node_id)
  else build node_id

let compile value = match value.root with
  | None -> Error "editable graph has no output node"
  | Some node_id -> compile_node value ~node_id

let replace_node node value =
  let id = Node.id node in
  match Id_map.find_opt id value.entries with
  | None -> Error (Printf.sprintf "editable graph has no node #%d" id)
  | Some (entry : entry) ->
      let arity = List.length (Node.inputs node) in
      if entry.factory = None && arity <> Array.length entry.inputs then Error (Printf.sprintf
          "replacement node %S changed input arity from %d to %d"
          (Node.label node) (Array.length entry.inputs) arity)
      else Ok { value with entries = Id_map.add id { entry with node } value.entries }

let apply_parameters value ~node_id changes =
  match find value ~node_id with
  | None -> Error (Printf.sprintf "editable graph has no node #%d" node_id)
  | Some node -> Result.bind (Node.apply_parameters node changes)
      (fun (node, effects) -> Result.map (fun value -> value, effects)
        (replace_node node value))

let add_node ?inputs ?factory node value =
  let id = Node.id node in
  if Id_map.mem id value.entries then Error (Printf.sprintf
      "editable graph already contains node #%d" id)
  else
    let arity = match factory with
      | None -> List.length (Node.inputs node)
      | Some factory -> Array.length factory.requirements in
    let inputs = match inputs with
      | Some inputs -> Array.copy inputs
      | None -> Node.inputs node |> List.map (fun input ->
          let id = Node.id input in
          if Id_map.mem id value.entries then Some id else None)
          |> Array.of_list in
    if Array.length inputs <> arity then Error (Printf.sprintf
        "new node %S expects %d inputs, received %d slots"
        (Node.label node) arity (Array.length inputs))
    else
      let missing = Array.find_opt (function
        | Some source -> not (Id_map.mem source value.entries)
        | None -> false) inputs in
      match missing with
      | Some (Some source) -> Error (Printf.sprintf
          "new node %S references missing node #%d" (Node.label node) source)
      | Some None -> assert false
      | None -> Ok { value with
          entries = Id_map.add id { node; inputs; factory } value.entries;
          order_rev = id :: value.order_rev }

let remove_nodes ids value =
  let removed = List.fold_left (fun set id -> Id_set.add id set)
      Id_set.empty ids in
  let entries = Id_map.filter_map (fun id (entry : entry) ->
    if Id_set.mem id removed then None
    else
      let inputs = Array.map (function
        | Some input when Id_set.mem input removed -> None
        | input -> input) entry.inputs in
      Some { entry with inputs }) value.entries in
  { entries;
    order_rev = List.filter (fun id -> not (Id_set.mem id removed)) value.order_rev;
    root = Option.bind value.root (fun id ->
      if Id_set.mem id removed then None else Some id) }

let depends_on value ~node_id ~candidate =
  let seen = Hashtbl.create 16 in
  let rec visit id =
    id = candidate || if Hashtbl.mem seen id then false else begin
      Hashtbl.add seen id ();
      match Id_map.find_opt id value.entries with
      | None -> false
      | Some (entry : entry) -> Array.exists (function
          | None -> false | Some input -> visit input) entry.inputs
    end
  in
  visit node_id

let rebuild_if_connected entries (entry : entry) inputs =
  let nodes = Array.make (Array.length inputs) entry.node in
  let complete = ref true in
  Array.iteri (fun index -> function
    | None -> complete := false
    | Some id ->
        (match Id_map.find_opt id entries with
         | None -> complete := false
         | Some (source : entry) -> nodes.(index) <- source.node)) inputs;
  if !complete then Node.Private.rebuild_with_inputs entry.node nodes
  else entry.node

let copy_nodes ids value =
  let selected = List.fold_left (fun selected id -> Id_set.add id selected)
      Id_set.empty ids in
  if Id_set.is_empty selected then Error "no nodes are selected"
  else match List.find_opt (fun id -> not (Id_map.mem id value.entries)) ids with
    | Some id -> Error (Printf.sprintf "editable graph has no node #%d" id)
    | None ->
        let fragment_entries = inspect value |> List.filter_map (fun info ->
          if not (Id_set.mem info.id selected) then None else
          let entry = Id_map.find info.id value.entries in
          let inputs = Array.map (function
            | Some source when Id_set.mem source selected -> Some source
            | Some _ | None -> None) entry.inputs in
          Some (info.id, { entry with inputs })) in
        let fragment_root = Option.bind value.root (fun id ->
          if Id_set.mem id selected then Some id else None) in
        Ok { fragment_entries; fragment_root }

let paste fragment value =
  if fragment.fragment_entries = [] then Error "cannot paste an empty node fragment"
  else
    let clones = List.map (fun (old_id, (entry : entry)) ->
      let placeholders = Array.make (Array.length entry.inputs) entry.node in
      old_id, Node.Private.clone_with_inputs entry.node placeholders,
      entry.inputs, entry.factory)
        fragment.fragment_entries in
    let remap = List.fold_left (fun remap (old_id, node, _, _) ->
      Id_map.add old_id (Node.id node) remap) Id_map.empty clones in
    let appended_ids = List.map (fun (_, node, _, _) -> Node.id node) clones in
    let entries = List.fold_left (fun entries (_, node, inputs, factory) ->
      let inputs = Array.map (function
        | None -> None
        | Some old_id -> Id_map.find_opt old_id remap) inputs in
      Id_map.add (Node.id node) { node; inputs; factory } entries)
        value.entries clones in
    let entries = List.fold_left (fun entries (_, node, _, _) ->
      let id = Node.id node in
      let entry = Id_map.find id entries in
      let node = rebuild_if_connected entries entry entry.inputs in
      Id_map.add id { entry with node } entries) entries clones in
    let mapping = List.map (fun (old_id, node, _, _) ->
      old_id, Node.id node) clones in
    let root = match value.root, fragment.fragment_root with
      | Some root, _ -> Some root
      | None, Some old_id -> Id_map.find_opt old_id remap
      | None, None -> None in
    Ok ({ entries; root;
          order_rev = List.rev_append appended_ids value.order_rev }, mapping)

let connect ~source ~consumer ~input_index value =
  if not (Id_map.mem source value.entries) then Error (Printf.sprintf
      "editable graph has no source node #%d" source)
  else match Id_map.find_opt consumer value.entries with
    | None -> Error (Printf.sprintf "editable graph has no consumer node #%d" consumer)
    | Some (entry : entry) when input_index < 0
        || input_index >= Array.length entry.inputs ->
        Error (Printf.sprintf "node %S has no input %d"
          (Node.label entry.node) input_index)
    | Some _ when depends_on value ~node_id:source ~candidate:consumer ->
        Error "connection would create a procedural cycle"
    | Some (entry : entry) ->
        let inputs = Array.copy entry.inputs in
        inputs.(input_index) <- Some source;
        let node = rebuild_if_connected value.entries entry inputs in
        Ok { value with entries = Id_map.add consumer { entry with node; inputs }
             value.entries }

let disconnect ~consumer ~input_index value =
  match Id_map.find_opt consumer value.entries with
  | None -> Error (Printf.sprintf "editable graph has no consumer node #%d" consumer)
  | Some (entry : entry) when input_index < 0
      || input_index >= Array.length entry.inputs ->
      Error (Printf.sprintf "node %S has no input %d"
        (Node.label entry.node) input_index)
  | Some (entry : entry) ->
      let inputs = Array.copy entry.inputs in
      inputs.(input_index) <- None;
      Ok { value with entries = Id_map.add consumer { entry with inputs }
           value.entries }

let insert_on_connection ?factory connection node value =
  let arity = match factory with
    | None -> List.length (Node.inputs node)
    | Some factory -> Array.length factory.requirements in
  if arity <> 1 then Error (Printf.sprintf
      "node %S cannot be inserted on a wire because it has %d inputs"
      (Node.label node) arity)
  else match Id_map.find_opt connection.consumer value.entries with
    | None -> Error (Printf.sprintf "editable graph has no consumer node #%d"
        connection.consumer)
    | Some (consumer : entry) when connection.input_index < 0
        || connection.input_index >= Array.length consumer.inputs ->
        Error "selected connection input no longer exists"
    | Some (consumer : entry) when consumer.inputs.(connection.input_index)
        <> Some connection.source -> Error "selected connection is stale"
    | Some _ ->
        Result.bind (add_node ~inputs:[|Some connection.source|] ?factory node value)
          (connect ~source:(Node.id node) ~consumer:connection.consumer
             ~input_index:connection.input_index)

let factory ?operation ~key ~label ~category ~arity build =
  let operation = Option.value ~default:key operation in
  if String.trim key = "" || String.trim operation = ""
      || String.trim label = ""
      || category = []
      || List.exists (fun item -> String.trim item = "") category then
    invalid_arg "Edit_graph.factory names must not be blank";
  if arity < 0 then invalid_arg "Edit_graph.factory arity must be non-negative";
  { key; operation; label; category; requirements = Array.make arity Required;
    build = (fun inputs -> build (List.map Option.get inputs)) }

let factory_slots ?operation ~key ~label ~category ~inputs build =
  let operation = Option.value ~default:key operation in
  if String.trim key = "" || String.trim operation = ""
      || String.trim label = ""
      || category = []
      || List.exists (fun item -> String.trim item = "") category then
    invalid_arg "Edit_graph.factory_slots names must not be blank";
  if inputs = [] then invalid_arg
      "Edit_graph.factory_slots requires at least one input slot";
  { key; operation; label; category; requirements = Array.of_list inputs; build }

let factory_key (value : factory) = value.key
let factory_operation (value : factory) = value.operation
let factory_label (value : factory) = value.label
let factory_category (value : factory) = value.category
let factory_arity (value : factory) = Array.length value.requirements
let factory_inputs (value : factory) = Array.to_list value.requirements
let factory_ready (value : factory) inputs =
  List.length inputs = Array.length value.requirements
  && List.for_all2 (fun requirement input ->
    requirement = Optional || Option.is_some input)
      (Array.to_list value.requirements) inputs

let instantiate (value : factory) inputs =
  let arity = Array.length value.requirements in
  if List.length inputs <> arity then Error (Printf.sprintf
      "%s expects %d input%s" value.label arity
      (if arity = 1 then "" else "s"))
  else try Ok (value.build (List.map Option.some inputs)) with
    | Invalid_argument message -> Error message
    | Failure message -> Error message

let disconnected_placeholder () =
  Node.Private.make ~label:"disconnected input"
    ~operation:"disconnected_input" ~version:1 ~parameters:""
    ~cook_mode:Node.Generator ~dependencies:Context.Dependencies.static
    ~inputs:[||] (fun ~node_id:_ _ _ -> Error (Diagnostic.error
      ~code:"disconnected_input" "node input is not connected"))

let instantiate_optional (value : factory) inputs =
  let arity = Array.length value.requirements in
  if List.length inputs <> arity then Error (Printf.sprintf
      "%s expects %d input slot%s" value.label arity
      (if arity = 1 then "" else "s"))
  else
    let placeholder = lazy (disconnected_placeholder ()) in
    let inputs = List.map2 (fun requirement input -> match requirement, input with
      | _, Some node -> Some node
      | Optional, None -> None
      | Required, None -> Some (Lazy.force placeholder))
        (Array.to_list value.requirements) inputs in
    try Ok (value.build inputs) with
    | Invalid_argument message -> Error message
    | Failure message -> Error message
