open Prismel
open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error message -> fail message

let () =
  let source = Sop.box ~label:"source" ~size:(Vec3.create 1. 1. 1.) () in
  let middle = Sop.null ~label:"middle" source in
  let output = Sop.null ~label:"output" middle in
  let document = Edit_graph.of_graph output in
  check (Edit_graph.root document = Some (Node.id output)
      && List.length (Edit_graph.inspect document) = 3)
    "editable graph did not import the compiled DAG";
  let disconnected = Edit_graph.disconnect ~consumer:(Node.id middle)
      ~input_index:0 document |> get in
  check (Result.is_error (Edit_graph.compile disconnected)
      && Result.is_ok (Edit_graph.compile_node disconnected
        ~node_id:(Node.id source)))
    "editable graph did not retain a cookable branch around a disconnected slot";
  let reconnected = Edit_graph.connect ~source:(Node.id source)
      ~consumer:(Node.id middle) ~input_index:0 disconnected |> get in
  check (Result.is_ok (Edit_graph.compile reconnected))
    "editable graph did not compile after reconnecting its slot";
  check (Result.is_error (Edit_graph.connect ~source:(Node.id middle)
      ~consumer:(Node.id middle) ~input_index:0 reconnected))
    "editable graph accepted a self cycle";
  let inserted = Sop.null ~label:"inserted" source in
  let connection = Edit_graph.{ source = Node.id source;
    consumer = Node.id middle; input_index = 0 } in
  let inserted_document = Edit_graph.insert_on_connection connection inserted
      reconnected |> get in
  let inserted_inputs = Edit_graph.inputs inserted_document
      ~node_id:(Node.id inserted) |> Option.get in
  let middle_inputs = Edit_graph.inputs inserted_document
      ~node_id:(Node.id middle) |> Option.get in
  check (inserted_inputs = [|Some (Node.id source)|]
      && middle_inputs = [|Some (Node.id inserted)|]
      && Result.is_ok (Edit_graph.compile inserted_document))
    "editable graph wire insertion was not atomic";
  let removed = Edit_graph.remove_nodes [Node.id inserted] inserted_document in
  check (Edit_graph.find removed ~node_id:(Node.id inserted) = None
      && Edit_graph.inputs removed ~node_id:(Node.id middle) = Some [|None|]
      && Result.is_error (Edit_graph.compile removed))
    "editable graph node deletion did not leave an explicit disconnected slot";
  let box_factory = Edit_graph.factory ~key:"box" ~label:"Box"
      ~category:["Create"] ~arity:0 (function
        | [] -> Sop.box ~size:(Vec3.create 1. 1. 1.) ()
        | _ -> assert false) in
  check (Edit_graph.factory_arity box_factory = 0
      && Result.is_ok (Edit_graph.instantiate box_factory []))
    "editable graph factory did not instantiate its declared arity";
  let null_factory = Edit_graph.factory ~key:"null" ~label:"Null"
      ~category:["Utility"] ~arity:1 (function
        | [input] -> Sop.null input | _ -> assert false) in
  let loose_null = Edit_graph.instantiate_optional null_factory [None] |> get in
  let loose_document = Edit_graph.add_node ~inputs:[|None|] loose_null document
      |> get in
  check (Edit_graph.inputs loose_document ~node_id:(Node.id loose_null)
      = Some [|None|])
    "factory could not create a node with a disconnected input";
  let match_size_factory = Edit_graph.factory_slots ~key:"match_size"
      ~label:"Match Size" ~category:["Modify"]
      ~inputs:[Edit_graph.Required; Optional] (function
        | [Some input; target] -> Sop.match_size ?target input
        | _ -> invalid_arg "Match Size requires its geometry input") in
  let loose_match = Edit_graph.instantiate_optional match_size_factory
      [None; None] |> get in
  let optional_document = Edit_graph.add_node ~factory:match_size_factory
      ~inputs:[|None; None|] loose_match document |> get
    |> Edit_graph.connect ~source:(Node.id source)
         ~consumer:(Node.id loose_match) ~input_index:0 |> get in
  let without_target = Edit_graph.compile_node optional_document
      ~node_id:(Node.id loose_match) |> get in
  check (List.length (Node.inputs without_target) = 1
      && Edit_graph.factory_inputs match_size_factory
         = [Edit_graph.Required; Optional])
    "optional factory slot was treated as a disconnected required input";
  let optional_document = Edit_graph.connect ~source:(Node.id middle)
      ~consumer:(Node.id loose_match) ~input_index:1 optional_document |> get in
  let with_target = Edit_graph.compile_node optional_document
      ~node_id:(Node.id loose_match) |> get in
  check (Node.id with_target = Node.id loose_match
      && List.length (Node.inputs with_target) = 2)
    "connecting an optional slot did not rebuild the physical SOP inputs";
  let optional_document = Edit_graph.disconnect ~consumer:(Node.id loose_match)
      ~input_index:1 optional_document |> get in
  let without_target_again = Edit_graph.compile_node optional_document
      ~node_id:(Node.id loose_match) |> get in
  check (Node.id without_target_again = Node.id loose_match
      && List.length (Node.inputs without_target_again) = 1)
    "disconnecting an optional slot did not restore the unary SOP";
  let fragment = Edit_graph.copy_nodes [Node.id source; Node.id middle]
      reconnected |> get in
  let pasted, mapping = Edit_graph.paste fragment reconnected |> get in
  let pasted_source = List.assoc (Node.id source) mapping
  and pasted_middle = List.assoc (Node.id middle) mapping in
  check (pasted_source <> Node.id source && pasted_middle <> Node.id middle
      && Edit_graph.inputs pasted ~node_id:pasted_middle
         = Some [|Some pasted_source|]
      && List.length (Edit_graph.inspect pasted) = 5)
    "subgraph paste did not assign fresh ids and preserve internal wiring";
  let external_fragment = Edit_graph.copy_nodes [Node.id middle] reconnected
      |> get in
  let pasted, mapping = Edit_graph.paste external_fragment reconnected |> get in
  check (Edit_graph.inputs pasted ~node_id:(List.assoc (Node.id middle) mapping)
      = Some [|None|])
    "subgraph paste retained an external connection instead of a loose slot";
  print_endline "editable graph tests passed"
