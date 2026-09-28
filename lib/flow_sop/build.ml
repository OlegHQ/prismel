open Flow
module Edit = Procedural.Edit_graph
module Port_map = Port.Map
module String_map = Network.String_map

let fail diagnostic = invalid_arg (Diagnostic.to_string diagnostic)
let get = function Ok value -> value | Error diagnostic -> fail diagnostic
let geometry = function Ok value -> value | Error message ->
  invalid_arg ("Flow build: " ^ message)
let port node path = Port.{node; path}

type value =
  | Source of Port.t
  | Literal of Param.value
  | Vector of value list
  | Expression of Expr.t
  | Nil

type built = Node of int * (string * Port_type.t) list | Value of value
type write = Port.t * value

type state = {
  factories : Edit.factory list;
  local_factories : Edit.factory list;
  definitions : Network.definition String_map.t;
  mutable next_id : int;
  mutable geometry : Edit.t;
  mutable values : Graph.t;
  mutable instances : Network.instance Network.Int_map.t;
  mutable geometry_outputs : string Port_map.t;
  mutable writes : write list;
}

let fresh state =
  let id = state.next_id in
  state.next_id <- id + 1;
  id

let find_factory factories key =
  match List.find_opt (fun factory -> Edit.factory_key factory = key) factories with
  | Some factory -> factory
  | None -> invalid_arg ("Flow build: linked catalog has no " ^ key)

let linked_factory state kind = match String.split_on_char '/' kind with
  | ["sop"; key] -> find_factory state.factories key, None
  | ["user"; name] ->
      (match List.find_opt (fun factory -> Edit.factory_key factory = name)
          state.local_factories with
       | Some factory -> factory, None
       | None ->
      let definition = match String_map.find_opt name state.definitions with
        | Some definition -> definition
        | None -> invalid_arg ("Flow build: no definition " ^ name) in
      let factory = match Compound_node.factories ~name
          ~inputs:definition.inputs ~outputs:definition.outputs with
        | [_; _; factory] -> factory | _ -> assert false in
      factory, Some name)
  | _ -> invalid_arg ("Flow build: invalid geometry kind " ^ kind)

let output built = match built with
  | Value value -> value
  | Node (id, [name, _]) -> Source (port id name)
  | Node _ -> invalid_arg "Flow build: choose a named output"

let rec count_term (term : Check.term) =
  let children = match term.node with
    | Check.Call call -> List.map snd call.arguments
    | Vector terms -> terms
    | Literal _ | Nil | Expression _ | Reference _ -> [] in
  (match term.node with Check.Call _ -> 1 | _ -> 0) +
  List.fold_left (fun count term -> count + count_term term) 0 children

let count_graph (graph : Check.graph) =
  List.fold_left (fun count binding -> count + count_term binding.Check.term)
    0 graph.bindings +
  List.fold_left (fun count term -> count + count_term term) 0 graph.results

let make_state ~factories ~local_factories ~definitions = {
  factories; local_factories; definitions; next_id = 1; geometry = Edit.empty;
  values = Graph.empty; instances = Network.Int_map.empty;
  geometry_outputs = Port_map.empty; writes = [];
}

let add_marker state factory =
  let inputs = List.init (Edit.factory_arity factory) (fun _ -> None) in
  let node = geometry (Edit.instantiate_optional factory inputs) in
  let id = Procedural.Node.id node in
  state.geometry <- geometry (Edit.add_node ~factory
    ~inputs:(Array.make (List.length inputs) None) node state.geometry);
  id

let rec evaluate state env (term : Check.term) : built = match term.node with
  | Literal literal -> Value (Literal literal)
  | Nil -> Value Nil
  | Vector terms -> Value (Vector (List.map (fun term ->
      output (evaluate state env term)) terms))
  | Expression expression -> Value (Expression expression)
  | Reference (name, path) ->
      (match List.assoc_opt name env with
       | Some (Node (id, outputs)) when List.mem_assoc path outputs ->
           Value (Source (port id path))
       | Some (Value value) -> Value value
       | _ -> invalid_arg ("Flow build: unbound output " ^ name ^ "." ^ path))
  | Call call ->
      let arguments = List.map (fun (name, term) ->
        name, output (evaluate state env term)) call.arguments in
      let id = fresh state in
      (match String.split_on_char '/' call.kind with
       | ["value"; key] ->
           let kind = get (Value_kind.of_key key) in
           let node = get (Graph.node ~id ~label:(Value_kind.label kind) kind) in
           state.values <- get (Graph.add_node node state.values);
           List.iter (fun (name, value) -> state.writes <-
             (port id name, value) :: state.writes) arguments;
           Node (id, Value_kind.outputs kind)
       | ["sop"; _] | ["user"; _] ->
           let factory, instance = linked_factory state call.kind in
           let slots = Edit.factory_slot_names factory in
           let inputs = List.map (fun _ -> None) slots in
           let node = geometry (Edit.instantiate_optional factory inputs)
             |> geometry_id id in
           let node = Procedural.Node.relabel (Edit.factory_label factory) node in
           state.geometry <- geometry (Edit.add_node ~factory
             ~inputs:(Array.make (List.length slots) None) node state.geometry);
           Option.iter (fun name -> state.instances <- Network.Int_map.add id
             Network.{definition = name; literals = String_map.empty}
             state.instances) instance;
           List.iter (fun (name, value) ->
             match List.find_index (( = ) name) slots with
             | Some index -> (match value with
                 | Nil -> ()
                 | Source source ->
                     state.geometry <- geometry (Edit.connect
                       ~source:source.node ~consumer:id ~input_index:index
                       state.geometry);
                     if source.path <> "geo" then
                       state.geometry_outputs <- Port_map.add (port id name)
                         source.path state.geometry_outputs
                 | _ -> invalid_arg ("Flow build: geometry slot " ^ name ^
                     " has no geometry source"))
             | None -> state.writes <- (port id name, value) :: state.writes)
             arguments;
           if call.bypass then state.geometry <- geometry
             (Edit.set_bypass state.geometry ~node_id:id true);
           let outputs = match instance with
             | None -> ["geo", Port_type.Geometry]
             | Some name -> (String_map.find name state.definitions).outputs
                 |> List.map (fun (p : Network.interface_port) -> p.name, p.ty) in
           Node (id, outputs)
       | _ -> invalid_arg ("Flow build: invalid call " ^ call.kind))

and geometry_id id node = geometry (Procedural.Node.Private.restore_id id node)

let add_result state marker name value = match value with
  | Nil -> ()
  | Source source when marker <> None ->
      let marker = Option.get marker in
      let slots = Option.get (Edit.node_slot_names state.geometry ~node_id:marker) in
      (match List.find_index (( = ) name) slots with
       | Some index ->
           state.geometry <- geometry (Edit.connect ~source:source.node
             ~consumer:marker ~input_index:index state.geometry);
           if source.path <> "geo" then state.geometry_outputs <-
             Port_map.add (port marker name) source.path state.geometry_outputs
       | None -> state.writes <- (port marker name, value) :: state.writes)
  | _ when marker <> None ->
      state.writes <- (port (Option.get marker) name, value) :: state.writes
  | _ -> ()

let apply_write network (target, value) =
  let scalar network target literal =
    let parameter = get (Network.parameter network target) in
    let literal = match parameter.Port.ty, literal with
      | None, Param.Text_value text ->
          (match parameter.fields with
           | [{Param.kind = Param.Choice_view _; _}] -> Param.Choice_value text
           | _ -> literal)
      | None, _ -> literal
      | Some _, Param.Text_value _ | Some _, Param.Choice_value _ -> literal
      | Some _, _ ->
          let typed = match literal with
            | Param.Float_value value -> Port_type.Float_value value
            | Int_value value -> Int_value value
            | Bool_value value -> Bool_value value
            | Text_value _ | Choice_value _ -> assert false in
          let normalized, _ = get (Port.normalize parameter typed) in
          (match normalized with
           | Port_type.Float_value value -> Param.Float_value value
           | Int_value value -> Param.Int_value value
           | Bool_value value -> Param.Bool_value value
           | Vec3_value _ -> invalid_arg "Flow build: scalar became vector") in
    get (Network.set_literal ~target (Port.Scalar literal) network) in
  let rec write network target = function
    | Nil -> network
    | Source source -> get (Network.connect_value ~source ~target network)
    | Expression expression -> get (Network.set_expr ~target expression network)
    | Literal literal -> scalar network target literal
    | Vector [x;y;z] ->
        let parts = ["x", x; "y", y; "z", z] in
        List.fold_left (fun network (axis, value) ->
          write network {target with path = target.path ^ "." ^ axis} value)
          network parts
    | Vector _ -> invalid_arg "Flow build: vector needs three components" in
  write network target value

let finish state =
  let network = get (Network.of_parts ~geometry:state.geometry
    ~values:state.values ~drives:Port_map.empty
    ~geometry_outputs:state.geometry_outputs ~instances:state.instances) in
  List.fold_left apply_write network (List.rev state.writes)

let interface_port (name, ty, default) : Network.interface_port =
  let rec literal (term : Check.term) = match term.node with
    | Check.Literal value -> Some (Port.Scalar value)
    | Vector [a;b;c] ->
        (match literal a, literal b, literal c with
         | Some (Port.Scalar (Param.Float_value a)),
           Some (Port.Scalar (Param.Float_value b)),
           Some (Port.Scalar (Param.Float_value c)) -> Some (Port.Vector (a,b,c))
         | _ -> None)
    | _ -> None in
  {name; ty; default = Option.bind default literal;
   label = String.capitalize_ascii name; soft = None}

let build_graph state ?markers (graph : Check.graph) ~outputs =
  let env = ref (match markers with
    | None -> []
    | Some (inputs, ports, _) -> List.map (fun (p : Network.interface_port) ->
        p.name, Value (Source (port inputs p.name))) ports) in
  List.iter (fun binding ->
    let built = evaluate state !env binding.Check.term in
    (match built with
     | Node (id, _) when Graph.find state.values ~node_id:id <> None ->
         state.values <- get (Graph.relabel state.values ~node_id:id binding.name)
     | Node (id, _) ->
         let node = Option.get (Edit.find state.geometry ~node_id:id) in
         state.geometry <- geometry (Edit.replace_node
           (Procedural.Node.relabel binding.name node) state.geometry)
     | Value _ -> ());
    env := (binding.name, built) :: !env) graph.bindings;
  let results = List.map (fun term -> output (evaluate state !env term))
    graph.results in
  List.iter2 (fun (name, _) value ->
    add_result state (Option.map (fun (_, _, outputs) -> outputs) markers)
      name value) outputs results;
  let display = match outputs, results with
    | [(_, Port_type.Geometry)], [Source source] -> Some source.node
    | _ -> None in
  Option.iter (fun id -> state.geometry <- geometry
    (Edit.set_root id state.geometry)) display;
  finish state, display

let program ~factories ?(local_factories = []) ~manifest_digest
    (checked : Check.program) =
  let _, linked_digest = get (Manifest.generate factories) in
  if linked_digest <> manifest_digest then invalid_arg
    "Flow catalog manifest is stale; regenerate lib/sop_catalog/flow_manifest.sexp";
  let count = count_graph checked.graph +
    List.fold_left (fun n (definition : Check.definition) ->
      n + count_graph definition.graph)
      0 checked.definitions in
  if count > 0 then geometry (Procedural.Node.Private.reserve_id count);
  let next_id = ref 1 and definitions = ref String_map.empty in
  List.iter (fun (definition : Check.definition) ->
    let inputs = List.map interface_port definition.inputs in
    let outputs = List.map (fun (name, ty) -> interface_port
      (name, ty, None)) definition.outputs in
    let name = definition.graph.name in
    let markers = Compound_node.factories ~name ~inputs ~outputs in
    let state = make_state ~factories ~local_factories
      ~definitions:!definitions in
    state.next_id <- !next_id;
    let input_factory, output_factory = match markers with
      | [input; output; _] -> input, output | _ -> assert false in
    let input_id = add_marker state input_factory in
    let output_id = add_marker state output_factory in
    let body, _ = build_graph state
      ~markers:(input_id, inputs, output_id) definition.graph
      ~outputs:definition.outputs in
    next_id := state.next_id;
    definitions := String_map.add name
      {Network.name = name; context = definition.graph.context;
        inputs; outputs; body}
      !definitions) checked.definitions;
  let state = make_state ~factories ~local_factories
    ~definitions:!definitions in
  state.next_id <- !next_id;
  let network, display = build_graph state checked.graph
    ~outputs:["geo", Port_type.Geometry] in
  Program.{name = checked.graph.name; network; display;
    definitions = !definitions}
