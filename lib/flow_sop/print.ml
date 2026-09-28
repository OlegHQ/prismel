type t = { text : string; binding_lines : (int * int) list }
exception Cannot_print of Flow.Diagnostic.t
let fail code message = raise (Cannot_print (Flow.Diagnostic.error ~code message))
let require = function Ok value -> value | Error diagnostic -> raise (Cannot_print diagnostic)

let quote value =
  let buffer = Buffer.create (String.length value + 2) in
  Buffer.add_char buffer '"';
  String.iter (function
    | '"' -> Buffer.add_string buffer "\\\""
    | '\\' -> Buffer.add_string buffer "\\\\"
    | '\n' -> Buffer.add_string buffer "\\n"
    | character -> Buffer.add_char buffer character) value;
  Buffer.add_char buffer '"'; Buffer.contents buffer
let literal = function
  | Param.Bool_value true -> "true" | Param.Bool_value false -> "false"
  | Param.Int_value value -> string_of_int value
  | Param.Float_value value -> Flow.Expr.sexp_number value
  | Param.Text_value value | Param.Choice_value value -> quote value

let binding_base label =
  let source = String.lowercase_ascii label in
  let buffer = Buffer.create (String.length source) in
  let previous_separator = ref false in
  String.iter (function
    | ('a' .. 'z' | '0' .. '9' | '_') as character ->
        Buffer.add_char buffer character; previous_separator := false
    | _ when not !previous_separator ->
        Buffer.add_char buffer '_'; previous_separator := true
    | _ -> ()) source;
  let name = Buffer.contents buffer in
  let name = if name = "" then "node" else name in
  let name = if Flow.Symbol.valid_name name then name else "n" ^ name in
  if Flow.Symbol.reserved name then "n_" ^ name else name

let node_ids network =
  let geometry = Procedural.Edit_graph.inspect network.Network.geometry
    |> List.map (fun (node : Procedural.Edit_graph.node_info) -> node.id) in
  let values = Flow.Graph.inspect network.values
    |> List.map (fun (node : Flow.Graph.node) -> node.id) in
  List.sort Int.compare (geometry @ values)

let is_structural network id =
  match Procedural.Edit_graph.find network.Network.geometry ~node_id:id with
  | None -> false
  | Some node -> List.mem (Procedural.Node.operation node)
      ["flow_inputs"; "flow_outputs"]

let dependencies network id =
  let geometry = match Procedural.Edit_graph.inputs network.Network.geometry
      ~node_id:id with
    | None -> [] | Some inputs -> Array.to_list inputs |> List.filter_map Fun.id in
  let parameters = require (Network.parameters network ~node_id:id) in
  let values = List.concat_map (fun parameter ->
    let paths = parameter.Port.path :: List.map (fun component ->
      component.Port.path) (Port.components parameter) in
    List.filter_map (fun path ->
      match Port.Map.find_opt Port.{node = id; path} network.drives with
      | Some (Drive.Wire source) -> Some source.node
      | _ -> None) paths) parameters in
  geometry @ values

let order network =
  let visited = Hashtbl.create 64 and active = Hashtbl.create 64 in
  let result = ref [] in
  let rec visit id =
    if Hashtbl.mem active id then fail "E_CYCLE"
      (Printf.sprintf "Cannot print a cycle through node %d" id);
    if not (Hashtbl.mem visited id) then begin
      Hashtbl.add active id ();
      List.iter visit (dependencies network id);
      Hashtbl.remove active id;
      Hashtbl.add visited id ();
      if not (is_structural network id) then result := id :: !result
    end in
  List.iter visit (node_ids network);
  List.rev !result

let names network ids =
  let used = Hashtbl.create 64 and names = Hashtbl.create 64 in
  List.iter (fun id ->
    let label = match Flow.Graph.find network.Network.values ~node_id:id with
      | Some node -> node.label
      | None -> (match Procedural.Edit_graph.find network.geometry ~node_id:id with
          | Some node -> Procedural.Node.label node
          | None -> fail "E_UNBOUND" (Printf.sprintf "No node %d" id)) in
    let base = binding_base label in
    let rec unique suffix =
      let name = if suffix = 1 then base else base ^ "_" ^ string_of_int suffix in
      if Hashtbl.mem used name then unique (suffix + 1) else name in
    let name = unique 1 in
    Hashtbl.add used name (); Hashtbl.add names id name) ids;
  names

let reference ~definitions ~input_marker network names (source : Port.t) =
  if Some source.node = input_marker then source.path else
  let name = match Hashtbl.find_opt names source.node with
    | Some name -> name
    | None -> fail "E_UNBOUND" (Printf.sprintf "No binding for node %d" source.node) in
  let outputs = require (Network.outputs ~definitions network ~node_id:source.node) in
  match outputs with
  | [single, _] when single = source.path -> name
  | _ -> name ^ "." ^ source.path

let parameter_text ~definitions ~input_marker network names id parameter =
  let source path =
    match Port.Map.find_opt Port.{node = id; path} network.Network.drives with
    | Some (Drive.Expr expr) -> Some (Flow.Expr.sexp expr)
    | Some (Drive.Wire wire) -> Some (reference ~definitions ~input_marker
        network names Port.{node = wire.node; path = wire.output})
    | None -> None in
  match source parameter.Port.path with
  | Some text -> Some text
  | None ->
      (match parameter.Port.fields with
       | [field] ->
           if field.Param.current <> field.default then Some (literal field.current)
           else None
       | [x;y;z] ->
           let components = ["x",x; "y",y; "z",z] in
           let values = List.map (fun (axis, field) ->
             let path = parameter.path ^ "." ^ axis in
             source path, field) components in
           if List.exists (fun (drive, field) -> drive <> None ||
               field.Param.current <> field.default) values then
             Some ("[" ^ String.concat " " (List.map (fun (drive, field) ->
               Option.value ~default:(literal field.Param.current) drive) values) ^ "]")
           else None
       | _ -> fail "E_PORT" ("Invalid parameter " ^ parameter.path))

let kind_name ~qualified ~catalog ~definitions network id =
  let full = match Flow.Graph.find network.Network.values ~node_id:id with
    | Some node -> "value/" ^ Flow.Value_kind.key
        (Flow.Value_kind.kind node.parameters)
    | None ->
        (match Network.Int_map.find_opt id network.instances with
         | Some instance -> "user/" ^ instance.definition
         | None -> "sop/" ^ (match Procedural.Edit_graph.node_factory_key
             network.geometry ~node_id:id with
             | Some key -> key
             | None -> match Procedural.Edit_graph.find network.geometry ~node_id:id with
               | Some node -> Procedural.Node.operation node
               | None -> fail "E_UNBOUND" (Printf.sprintf "No node %d" id))) in
  if qualified then full else
  let short = match String.split_on_char '/' full with
    | [_; name] -> name | _ -> full in
  let used = List.map (fun (kind : Flow.Check.kind) -> kind.qualified)
      catalog.Flow.Check.kinds @
    (Network.String_map.bindings definitions
      |> List.map (fun (name, _) -> "user/" ^ name)) @
    List.map (fun node -> "value/" ^ Flow.Value_kind.key node)
      Flow.Value_kind.all in
  if List.exists (fun other -> other <> full &&
      String.ends_with ~suffix:("/" ^ short) other) used then full
  else short

let call_text ~qualified ~catalog ~definitions ~input_marker network names id =
  let math = match Flow.Graph.find network.Network.values ~node_id:id with
    | Some node when Flow.Value_kind.kind node.parameters = Flow.Value_kind.Math ->
        Some node | _ -> None in
  let math_sugar = match math with
    | None -> None
    | Some node ->
        let wired path = match Port.Map.find_opt Port.{node = id; path}
            network.drives with Some (Drive.Wire _) -> true | _ -> false in
        if not (wired "a" || wired "b") then None else
        let fields = Flow.Value_kind.fields node.parameters in
        let op_name = List.find_map (fun (field : Param.field_view) ->
          if field.name = "op" then match field.current with
            | Param.Choice_value name -> Some name | _ -> None
          else None) fields in
        let op_name = Option.value ~default:"mul" op_name in
        let op = match List.assoc_opt op_name Flow.Expr.operators with
          | Some op -> op | None -> fail "E_TYPE" ("Unknown math op " ^ op_name) in
        let symbol = match op with
          | Flow.Expr.Add -> "+" | Sub -> "-" | Mul -> "*" | Div -> "/"
          | _ -> op_name in
        let symbol = if qualified then "value/" ^ symbol else symbol in
        let argument path =
          let parameter = require (Network.parameter network Port.{node = id; path}) in
          match parameter_text ~definitions ~input_marker network names id parameter with
          | Some text -> text
          | None -> (match parameter.fields with
              | [field] -> literal field.Param.current
              | _ -> fail "E_PORT" ("Math has no " ^ path)) in
        let arguments = if Flow.Expr.arity op = 1 then [argument "a"]
          else [argument "a"; argument "b"] in
        Some ("(" ^ String.concat " " (symbol :: arguments) ^ ")") in
  match math_sugar with Some text -> text | None ->
  let kind = kind_name ~qualified ~catalog ~definitions network id in
  let slots = match Procedural.Edit_graph.node_slot_names network.Network.geometry
      ~node_id:id with None -> [] | Some slots -> slots in
  let inputs = match Procedural.Edit_graph.inputs network.geometry ~node_id:id with
    | None -> [||] | Some inputs -> inputs in
  let connected index path =
    if index >= Array.length inputs then None else
    Option.map (fun _ ->
      let source = match Network.geometry_source network Port.{node = id; path} with
        | Some source -> source
        | None -> fail "E_PORT" ("Missing geometry source for " ^ path) in
      reference ~definitions ~input_marker network names source) inputs.(index) in
  let slot_arguments = List.mapi (fun index path -> index, path, connected index path) slots in
  let later_connected = List.exists (fun (index, _, source) -> index > 0 &&
    source <> None) slot_arguments in
  let primary = match slot_arguments with
    | (_, _, Some source) :: _ -> [source]
    | (_, _, None) :: _ when later_connected -> ["nil"]
    | _ -> [] in
  let other_slots = List.filter_map (fun (index, path, source) ->
    if index = 0 then None else Option.map (fun source ->
      ":" ^ path ^ " " ^ source) source) slot_arguments in
  let parameters = require (Network.parameters network ~node_id:id) in
  let fields = List.filter_map (fun parameter ->
    Option.map (fun value -> ":" ^ parameter.Port.path ^ " " ^ value)
      (parameter_text ~definitions ~input_marker network names id parameter))
    parameters in
  let bypass = Procedural.Edit_graph.is_bypassed network.geometry ~node_id:id in
  (if bypass then "^:bypass " else "") ^ "(" ^
  String.concat " " (kind :: primary @ other_slots @ fields) ^ ")"

let render_body ~qualified ~catalog ~definitions ~input_marker network ~result =
  let ids = order network in
  let names = names network ids in
  let bindings = List.map (fun id ->
    id, Hashtbl.find names id,
    call_text ~qualified ~catalog ~definitions ~input_marker network names id) ids in
  let result = result names in
  let body = match bindings with
    | [] -> result
    | (_, first, form) :: rest ->
        "(let* [" ^ first ^ " " ^ form ^
        String.concat "" (List.map (fun (_, name, form) ->
          "\n         " ^ name ^ " " ^ form) rest) ^ "]\n    " ^ result ^ ")" in
  body, List.mapi (fun index (id, _, _) -> id, index) bindings

let port_literal = function
  | Port.Scalar value -> literal value
  | Port.Vector (x, y, z) ->
      "[" ^ String.concat " " (List.map Flow.Expr.sexp_number [x; y; z]) ^ "]"

let definition_text ~qualified ~catalog ~definitions (definition : Network.definition) =
  let network = definition.body in
  require (Network.validate network);
  let marker operation =
    Procedural.Edit_graph.inspect network.geometry
    |> List.find_opt (fun (info : Procedural.Edit_graph.node_info) ->
        info.operation = operation)
    |> function Some info -> info.id
      | None -> fail "E_INTERFACE" ("Definition " ^ definition.name ^
          " has no " ^ operation ^ " marker") in
  let inputs = marker "flow_inputs" and outputs = marker "flow_outputs" in
  let result names =
    let one (port : Network.interface_port) =
      let text = match port.ty with
        | Flow.Port_type.Geometry ->
            (match Network.geometry_source network Port.{node = outputs; path = port.name} with
             | Some source -> reference ~definitions ~input_marker:(Some inputs)
                 network names source
             | None -> fail "E_RESULT_TYPE"
                 ("Definition " ^ definition.name ^ " has no geometry output " ^ port.name))
        | _ ->
            let parameter = require (Network.parameter network
              Port.{node = outputs; path = port.name}) in
            (match parameter_text ~definitions ~input_marker:(Some inputs)
                network names outputs parameter with
             | Some text -> text
             | None -> (match port.default with
                 | Some default -> port_literal default
                 | None -> port_literal (Port.literal parameter))) in
      port.name, text in
    let results = List.map one definition.outputs in
    match results with
    | [] -> fail "E_RESULT_TYPE" ("Definition " ^ definition.name ^ " has no outputs")
    | [name, text] when List.mem name ["geo"; "out"] -> text
    | _ -> "(values " ^ String.concat " " (List.map (fun (name, text) ->
        ":" ^ name ^ " " ^ text) results) ^ ")" in
  let body, _ = render_body ~qualified ~catalog ~definitions
    ~input_marker:(Some inputs)
    network ~result in
  let ports = List.map (fun (port : Network.interface_port) ->
    "(" ^ port.name ^ " :" ^ String.lowercase_ascii
      (Flow.Port_type.name port.ty) ^
      Option.fold ~none:"" ~some:(fun default -> " " ^ port_literal default)
        port.default ^ ")") definition.inputs in
  "(defgraph " ^ definition.name ^ " :context " ^
    Flow.Context.name definition.context ^ "\n  [" ^ String.concat " " ports ^
    "]\n  " ^ body ^ ")"

let ordered_definitions definitions =
  let seen = Hashtbl.create 16 and active = Hashtbl.create 16 in
  let ordered = ref [] in
  let rec visit name =
    if Hashtbl.mem active name then fail "E_RECURSIVE"
      ("Compound " ^ name ^ " contains itself");
    if not (Hashtbl.mem seen name) then begin
      let (definition : Network.definition) = match
          Network.String_map.find_opt name definitions with
        | Some definition -> definition
        | None -> fail "E_UNBOUND" ("Missing compound " ^ name) in
      Hashtbl.add active name ();
      Network.Int_map.iter (fun _ instance -> visit instance.Network.definition)
        definition.body.instances;
      Hashtbl.remove active name;
      Hashtbl.add seen name ();
      ordered := definition :: !ordered
    end in
  Network.String_map.iter (fun name _ -> visit name) definitions;
  List.rev !ordered

let network ?(qualified = false) ~name ~context ~catalog ~display ~definitions network =
  try
    require (Network.validate network);
    if not (Flow.Symbol.valid_name name) then
      fail "E_BINDING_NAME" ("Graph name " ^ name ^ " is not a Flow symbol");
    let result names = match display with
      | Some id when Hashtbl.mem names id ->
          let outputs = require (Network.outputs ~definitions network ~node_id:id) in
          let geometry = List.find_opt (fun (_, ty) ->
            ty = Flow.Port_type.Geometry) outputs in
          (match geometry with
           | Some (path, _) -> reference ~definitions ~input_marker:None
               network names Port.{node = id; path}
           | None -> fail "E_RESULT_TYPE"
               (Printf.sprintf "Display node %d has no geometry output" id))
      | Some id -> fail "E_RESULT_TYPE"
          (Printf.sprintf "Display node %d has no binding" id)
      | None -> "nil" in
    let body, bindings = render_body ~qualified ~catalog ~definitions ~input_marker:None
      network ~result in
    let printed_definitions = List.map (definition_text ~qualified ~catalog ~definitions)
      (ordered_definitions definitions) in
    let prefix = if printed_definitions = [] then "" else
      String.concat "\n\n" printed_definitions ^ "\n\n" in
    let text = prefix ^ "(graph " ^ name ^ " :context " ^
      Flow.Context.name context ^ "\n  " ^ body ^ ")" in
    let prefix_lines = String.fold_left (fun count character ->
      if character = '\n' then count + 1 else count) 0 prefix in
    let binding_lines = List.map (fun (id, index) ->
      id, prefix_lines + index + 2) bindings in
    Ok {text; binding_lines}
  with Cannot_print diagnostic -> Error diagnostic
