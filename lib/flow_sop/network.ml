module Int_map = Map.Make (Int)
module Int_set = Set.Make (Int)
module String_map = Map.Make (String)
type interface_port = {
  name : string;
  ty : Flow.Port_type.t;
  default : Param.value option;
  label : string;
  soft : (float * float) option;
}
type instance = { definition : string; literals : Param.value String_map.t }
type t = {
  geometry : Procedural.Edit_graph.t;
  values : Flow.Graph.t;
  drives : Drive.t Port.Map.t;
  geometry_outputs : string Port.Map.t;
  instances : instance Int_map.t;
}
and definition = {
  name : string;
  context : Flow.Context.t;
  inputs : interface_port list;
  outputs : interface_port list;
  body : t;
}
type fragment = {
  geometry_fragment : Procedural.Edit_graph.fragment option;
  value_nodes : Flow.Graph.node list;
  fragment_drives : Drive.t Port.Map.t;
  fragment_geometry_outputs : string Port.Map.t;
  fragment_instances : instance Int_map.t;
}
let error code message = Error (Flow.Diagnostic.error ~code message)
let geometry_error result = Result.map_error (Flow.Diagnostic.error ~code:"E_GEOMETRY") result
let of_geometry geometry = {geometry; values = Flow.Graph.empty;
  drives = Port.Map.empty; geometry_outputs = Port.Map.empty;
  instances = Int_map.empty}
let geometry_source_id geometry (port : Port.t) =
  match Procedural.Edit_graph.node_slot_names geometry ~node_id:port.node,
    Procedural.Edit_graph.inputs geometry ~node_id:port.node with
  | Some slots, Some inputs ->
      Option.bind (List.find_index (String.equal port.path) slots) (fun index ->
        if index < Array.length inputs then inputs.(index) else None)
  | _ -> None
let geometry_source network target =
  Option.map (fun node -> {Port.node; path =
    Option.value ~default:"geo" (Port.Map.find_opt target network.geometry_outputs)})
    (geometry_source_id network.geometry target)
let fields network ~node_id = match Flow.Graph.find network.values ~node_id with
  | Some node -> Ok (Flow.Value_kind.fields node.parameters)
  | None -> match Procedural.Edit_graph.find network.geometry ~node_id with
      | Some node ->
          let fields = Procedural.Node.parameter_fields node in
          if fields <> [] then Ok fields else
          let fields = Procedural.Edit_graph.node_factory_fields network.geometry ~node_id in
          let literals = match Int_map.find_opt node_id network.instances with
            | Some instance -> instance.literals | None -> String_map.empty in
          Ok (List.map (fun (field : Param.field_view) ->
            {field with current = Option.value ~default:field.current
              (String_map.find_opt field.name literals)}) fields)
      | None -> error "E_UNBOUND" (Printf.sprintf "No node %d" node_id)
let parameters network ~node_id = Result.bind (fields network ~node_id) Port.parameters
let parameter network (port : Port.t) = Result.bind (parameters network ~node_id:port.node)
  (fun parameters -> Port.find_parameter parameters port.path)
let output_type network (port : Port.t) = match Flow.Graph.find network.values ~node_id:port.node with
  | Some node -> (match List.assoc_opt port.path (Flow.Graph.outputs node) with
      | Some ty -> Ok ty | None -> error "E_PORT" ("No value output " ^ port.path))
  | None -> match Procedural.Edit_graph.find network.geometry ~node_id:port.node with
      | Some _ when port.path = "geo" -> Ok Flow.Port_type.Geometry
      | Some _ ->
          let fields = Procedural.Edit_graph.node_factory_output_fields
            network.geometry ~node_id:port.node in
          Result.bind (Port.parameters fields) (fun parameters ->
            match Port.find_parameter parameters port.path with
            | Ok {Port.ty = Some ty; _} -> Ok ty
            | _ -> error "E_PORT" ("No value output " ^ port.path))
      | None -> error "E_UNBOUND" (Printf.sprintf "No source node %d" port.node)

let outputs ~definitions network ~node_id =
  match Flow.Graph.find network.values ~node_id with
  | Some node -> Ok (Flow.Graph.outputs node)
  | None -> match Procedural.Edit_graph.find network.geometry ~node_id with
      | None -> error "E_UNBOUND" (Printf.sprintf "No source node %d" node_id)
      | Some node ->
          if Procedural.Node.operation node = "flow_outputs" then Ok [] else
          let interface = match Int_map.find_opt node_id network.instances with
            | Some instance -> Some (instance.definition, `Outputs)
            | None when Procedural.Node.operation node = "flow_inputs" ->
                Some (Procedural.Node.parameters node, `Inputs)
            | None -> None in
          (match interface with
           | None -> Ok ["geo", Flow.Port_type.Geometry]
           | Some (name, role) ->
               (match String_map.find_opt name definitions with
                | None -> error "E_UNBOUND" ("Missing compound " ^ name)
                | Some definition ->
                    let ports = if role = `Inputs then definition.inputs
                      else definition.outputs in
                    Ok (List.map (fun (port : interface_port) -> port.name, port.ty) ports)))

type visit = Enter of int | Leave of int
let topological_values network =
  let nodes = Flow.Graph.inspect network.values in
  let dependencies = Port.Map.fold (fun (target : Port.t) drive dependencies -> match drive with
    | Drive.Wire source when Flow.Graph.find network.values ~node_id:target.node <> None
        && Flow.Graph.find network.values ~node_id:source.node <> None ->
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
  match Procedural.Edit_graph.find network.geometry ~node_id:target.node with
  | Some node when Procedural.Node.operation node = "flow_inputs" ->
      error "E_PORT" "Inputs marker has no value inputs"
  | _ ->
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
      let missing_instance = Int_map.find_first_opt (fun id ->
        Procedural.Edit_graph.find network.geometry ~node_id:id = None
        && Flow.Graph.find network.values ~node_id:id = None) network.instances in
      (match missing_instance with
       | Some (id, _) -> error "E_UNBOUND" (Printf.sprintf "No instance node %d" id)
       | None ->
      let literals = Int_map.fold (fun id (instance : instance) checked ->
        Result.bind checked (fun () ->
          let fields = Procedural.Edit_graph.node_factory_fields network.geometry
            ~node_id:id in
          String_map.fold (fun name value checked -> Result.bind checked (fun () ->
            match List.find_opt (fun (field : Param.field_view) ->
              field.name = name) fields with
            | None -> error "E_PORT" ("Unknown compound literal " ^ name)
            | Some field ->
                let valid = match field.kind, value with
                  | Param.Floating_view _, Param.Float_value number -> Float.is_finite number
                  | Integer_view _, Int_value _ | Toggle_view, Bool_value _ -> true
                  | _ -> false in
                if valid then Ok () else error "E_TYPE"
                  ("Invalid compound literal " ^ name))) instance.literals (Ok ())))
        network.instances (Ok ()) in
      Result.bind literals (fun () ->
      let geometry_ports = Port.Map.fold (fun target output checked ->
        Result.bind checked (fun () -> match geometry_source_id network.geometry target with
          | None -> error "E_PORT" ("No geometry wire to " ^ target.path)
          | Some source ->
              let is_interface = Int_map.mem source network.instances
                || match Procedural.Edit_graph.find network.geometry ~node_id:source with
                   | Some node -> Procedural.Node.operation node = "flow_inputs"
                   | None -> false in
              if output = "geo" || not (Flow.Symbol.valid_name output)
                || not is_interface then
                error "E_PORT" ("Invalid geometry output " ^ output)
              else Ok ())) network.geometry_outputs (Ok ()) in
      Result.bind geometry_ports (fun () ->
      let nodes = List.map (fun (node : Flow.Graph.node) -> node.id) value_nodes
        @ List.map (fun (node : Procedural.Edit_graph.node_info) -> node.id) (Procedural.Edit_graph.inspect network.geometry) in
      let checked = List.fold_left (fun checked id -> Result.bind checked (fun () ->
        Result.bind (parameters network ~node_id:id) (fun parameters ->
          let slots = Option.value (Procedural.Edit_graph.node_slot_names network.geometry ~node_id:id) ~default:[] in
          if List.exists (fun parameter -> List.mem parameter.Port.path slots) parameters then
            error "E_PORT" "A slot and parameter have the same name" else Ok ()))) (Ok ()) nodes in
      Result.bind checked (fun () -> Result.bind
        (Port.Map.fold (fun target drive checked -> Result.bind checked (fun () -> validate_drive network target drive))
          network.drives (Ok ())) (fun () -> Result.map (fun _ -> ()) (topological_values network))))))
let of_parts ~geometry ~values ~drives ~geometry_outputs ~instances =
  let network = {geometry; values; drives; geometry_outputs; instances} in
  Result.bind (validate network) (fun () ->
    Result.map (fun () -> network) (List.fold_left (fun checked (node : Flow.Graph.node) ->
      Result.bind checked (fun () -> geometry_error (Procedural.Node.Private.reserve_id node.id)))
      (Ok ()) (Flow.Graph.inspect values)))
let with_geometry geometry network =
  if geometry == network.geometry then Ok network else
    let geometry_outputs = Port.Map.filter (fun target _ ->
      match geometry_source_id network.geometry target with
      | None -> false
      | Some source -> geometry_source_id geometry target = Some source)
      network.geometry_outputs in
    let next = {network with geometry; geometry_outputs} in
    Result.map (fun () -> next) (validate next)
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
    let geometry_outputs = Port.Map.filter (fun target _ ->
      geometry_source_id geometry target <> None) network.geometry_outputs in
    Ok {geometry; values; drives; geometry_outputs; instances = Int_map.filter
      (fun id _ -> not (Int_set.mem id removed)) network.instances}
let connect_geometry ~(source : Port.t) ~consumer ~input_index network =
  let slots = Option.value ~default:[]
    (Procedural.Edit_graph.node_slot_names network.geometry ~node_id:consumer) in
  match List.nth_opt slots input_index with
  | None -> error "E_PORT" "No geometry input slot"
  | Some path ->
      let is_interface = Int_map.mem source.node network.instances
        || match Procedural.Edit_graph.find network.geometry ~node_id:source.node with
           | Some node -> Procedural.Node.operation node = "flow_inputs"
           | None -> false in
      if source.path <> "geo" && (not is_interface
        || not (Flow.Symbol.valid_name source.path)) then
        error "E_PORT" ("No geometry output " ^ source.path)
      else Result.bind (geometry_error (Procedural.Edit_graph.connect
        ~source:source.node ~consumer ~input_index network.geometry))
        (fun geometry ->
          let target = {Port.node = consumer; path} in
          let geometry_outputs = if source.path = "geo" then
            Port.Map.remove target network.geometry_outputs else
            Port.Map.add target source.path network.geometry_outputs in
          let next = {network with geometry; geometry_outputs} in
          Result.map (fun () -> next) (validate next))
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
      ~consumer:target.node ~input_index network.geometry)) (fun geometry ->
        with_geometry geometry network)
let set_literal ~(target : Port.t) value network =
  Result.bind (parameter network target) (fun parameter ->
    let changes = if Int_map.mem target.node network.instances then
      let typed = match value with
        | Port.Scalar (Param.Float_value value) -> Ok (Flow.Port_type.Float_value value)
        | Scalar (Param.Int_value value) -> Ok (Flow.Port_type.Int_value value)
        | Scalar (Param.Bool_value value) -> Ok (Flow.Port_type.Bool_value value)
        | Vector (x,y,z) -> Ok (Flow.Port_type.Vec3_value (x,y,z))
        | Scalar _ -> error "E_TYPE" "Compound literals must be Float, Int, Bool or Vec3" in
      Result.bind typed (fun typed -> Result.map snd (Port.normalize parameter typed))
    else Port.literal_changes parameter value in
    Result.bind changes (fun changes ->
    match Int_map.find_opt target.node network.instances with
    | Some instance ->
        let literals = List.fold_left (fun literals (name, value) ->
          String_map.add name value literals) instance.literals changes in
        Ok {network with instances = Int_map.add target.node
          {instance with literals} network.instances}
    | None -> match Flow.Graph.find network.values ~node_id:target.node with
      | Some _ -> Result.map (fun (values, _) -> if values == network.values then network else {network with values})
          (Flow.Graph.apply_parameters network.values ~node_id:target.node changes)
      | None -> Result.bind (Result.map_error (Flow.Diagnostic.error ~code:"E_TYPE")
          (Procedural.Edit_graph.apply_parameters network.geometry ~node_id:target.node changes))
          (fun (geometry, _) -> with_geometry geometry network)))

let set_number ~target number network =
  Result.bind (parameter network target) (fun parameter ->
    Result.bind (Port.normalize parameter (Flow.Port_type.Float_value number))
      (fun (value, _) ->
        let literal = match value with
          | Flow.Port_type.Float_value value -> Port.Scalar (Param.Float_value value)
          | Int_value value -> Port.Scalar (Param.Int_value value)
          | Bool_value value -> Port.Scalar (Param.Bool_value value)
          | Vec3_value (x,y,z) -> Port.Vector (x,y,z) in
        Result.bind (clear_drive ~target network) (set_literal ~target literal)))

(* ponytail: recursion follows the expression/value tree; report the stack
   ceiling until an explicit traversal is needed for very deep networks. *)
let fold ~target network = try
  let refuse node message = error "E_FOLD" (node.Flow.Graph.label ^ ": " ^ message) in
  let field node name = List.find_opt (fun (field : Param.field_view) -> field.name = name)
    (Flow.Value_kind.fields node.Flow.Graph.parameters) in
  let number node name = match field node name with
    | Some {current = Param.Float_value value; _} -> Ok value
    | _ -> refuse node ("Cannot read " ^ name) in
  let collected = ref Int_set.empty in
  let rec input node path =
    match Port.Map.find_opt {Port.node = node.Flow.Graph.id; path} network.drives with
    | Some (Drive.Expr expression) -> Ok expression
    | Some (Drive.Wire source) -> output {Port.node = source.node; path = source.output}
    | None -> Result.bind (number node path) Flow.Expr.num
  and output source =
    match Flow.Graph.find network.values ~node_id:source.Port.node with
    | None -> error "E_FOLD" (Printf.sprintf "Node %d is not a value node" source.node)
    | Some node ->
        let expression = match Flow.Value_kind.kind node.parameters, source.path with
          | Flow.Value_kind.Time, "t" ->
              (match Port.Map.find_opt {Port.node = node.id; path = "speed"} network.drives with
               | Some (Drive.Wire _) -> refuse node "time.speed has a wire"
               | _ -> Result.bind (input node "speed") (fun speed ->
                   match speed with
                   | Flow.Expr.Num 1. -> Ok Flow.Expr.time
                   | _ -> Flow.Expr.op Flow.Expr.Mul [Flow.Expr.time; speed]))
          | Flow.Value_kind.Value, "out" -> input node "v"
          | Flow.Value_kind.Math, "out" ->
              (match field node "op" with
               | Some {current = Param.Choice_value name; _} ->
                   (match List.assoc_opt name Flow.Expr.operators with
                    | None -> refuse node ("Unknown math operation " ^ name)
                    | Some operator ->
                        let paths = if Flow.Expr.arity operator = 1 then ["a"] else ["a";"b"] in
                        Result.bind (List.fold_left (fun result path ->
                          Result.bind result (fun expressions ->
                            Result.map (fun expression -> expression :: expressions) (input node path)))
                          (Ok []) paths) (fun reversed -> Flow.Expr.op operator (List.rev reversed)))
               | _ -> refuse node "Cannot read math operation")
          | _ -> refuse node "Only math, value and time outputs can fold" in
        Result.map (fun expression ->
          collected := Int_set.add node.id !collected; expression) expression in
  match Port.Map.find_opt target network.drives with
  | Some (Drive.Wire source) ->
      Result.bind (output {Port.node = source.node; path = source.output}) (fun expression ->
        let shared = Port.Map.fold (fun destination drive found -> match found, drive with
          | Some _, _ -> found
          | None, Drive.Wire source when Int_set.mem source.node !collected
              && not (Int_set.mem destination.node !collected || destination = target) ->
              Flow.Graph.find network.values ~node_id:source.node
          | _ -> None) network.drives None in
        match shared with
        | Some node -> refuse node "is also used outside this expression"
        | None ->
            let ids = Int_set.elements !collected in
            Result.bind (remove_nodes ids network) (fun network ->
              Result.map (fun network -> network, ids) (match expression with
                | Flow.Expr.Num number -> set_number ~target number network
                | _ -> set_expr ~target expression network)))
  | _ -> error "E_FOLD" ("Port " ^ target.path ^ " has no wire to fold")
  with Stack_overflow -> error "E_DEPTH" "Value chain is too deep to fold"

let unfold ~target network = try
  match Port.Map.find_opt target network.drives with
  | Some (Drive.Expr expression) ->
      let time_id = ref None and time_rows = ref [] and max_column = ref 0 in
      let positions = ref [] and next_row = ref 0. in
      let rec build column expression network = match expression with
        | Flow.Expr.Num number ->
            let row = !next_row in next_row := row +. 1.;
            Ok (network, None, Some number, row)
        | Flow.Expr.Time ->
            let row = !next_row in next_row := row +. 1.; time_rows := row :: !time_rows;
            (match !time_id with
             | Some id -> Ok (network, Some {Port.node = id; path = "t"}, None, row)
             | None -> Result.map (fun (network, id) ->
                 time_id := Some id; network, Some {Port.node = id; path = "t"}, None, row)
                 (add_value_node Flow.Value_kind.Time network))
        | Flow.Expr.Op (operator, arguments) ->
            max_column := max !max_column column;
            Result.bind (List.fold_left (fun result argument ->
              Result.bind result (fun (network, reversed) ->
                Result.map (fun (network, source, number, row) ->
                  network, (source, number, row) :: reversed)
                  (build (column + 1) argument network)))
              (Ok (network, [])) arguments) (fun (network, reversed) ->
                let children = List.rev reversed in
                let rows = List.map (fun (_, _, row) -> row) children in
                let row = (List.hd rows +. List.hd (List.rev rows)) /. 2. in
                Result.bind (add_value_node Flow.Value_kind.Math network) (fun (network, id) ->
                  let name = fst (List.find (fun (_, candidate) -> candidate = operator)
                    Flow.Expr.operators) in
                  Result.bind (set_literal ~target:{Port.node = id; path = "op"}
                    (Port.Scalar (Param.Choice_value name)) network) (fun network ->
                    let paths = if Flow.Expr.arity operator = 1 then ["a"] else ["a";"b"] in
                    Result.bind (List.fold_left2 (fun result path (source, number, _) ->
                      Result.bind result (fun network -> match source, number with
                        | Some source, _ -> connect_value ~source ~target:{Port.node = id; path} network
                        | None, Some number -> set_literal ~target:{Port.node = id; path}
                            (Port.Scalar (Param.Float_value number)) network
                        | None, None -> assert false)) (Ok network) paths children) (fun network ->
                      positions := (id, column, row) :: !positions;
                      Ok (network, Some {Port.node = id; path = "out"}, None, row))))) in
      Result.bind (build 1 expression network) (fun (network, source, number, root_row) ->
        let network = Result.bind (clear_drive ~target network) (fun network ->
          match source, number with
          | Some source, _ -> connect_value ~source ~target network
          | None, Some number -> set_number ~target number network
          | None, None -> assert false) in
        Result.map (fun network ->
          let positions = match !time_id with
            | None -> !positions
            | Some id ->
                let rows = !time_rows in
                let average = List.fold_left (+.) 0. rows /. float (List.length rows) in
                (id, !max_column + 1, average) :: !positions in
          network, List.map (fun (id, column, row) -> id, column, row -. root_row) positions)
          network)
  | _ -> error "E_UNFOLD" ("Port " ^ target.path ^ " has no expression to unfold")
  with Stack_overflow -> error "E_DEPTH" "Expression is too deep to unfold"

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
        let fragment_instances = Int_map.filter (fun id _ -> Int_set.mem id selected)
          network.instances in
        let fragment_geometry_outputs = Port.Map.filter (fun target _ ->
          Int_set.mem target.node selected && match geometry_source_id network.geometry target with
          | Some source -> Int_set.mem source selected | None -> false)
          network.geometry_outputs in
        {geometry_fragment; value_nodes; fragment_drives;
          fragment_geometry_outputs; fragment_instances}) geometry_fragment)
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
      let instances = Int_map.fold (fun old_id instance instances ->
        Int_map.add (Int_map.find old_id remap) instance instances)
        fragment.fragment_instances network.instances in
      let geometry_outputs = Port.Map.fold (fun target output geometry_outputs ->
        Port.Map.add {target with node = Int_map.find target.node remap}
          output geometry_outputs) fragment.fragment_geometry_outputs
        network.geometry_outputs in
      let next = {geometry; values; drives; geometry_outputs; instances} in
      Result.map (fun () -> next, List.sort (fun (a,_) (b,_) -> Int.compare a b) mapping) (validate next)))
