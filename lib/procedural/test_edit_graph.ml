open Prismel
open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error message -> fail message

let run () =
  let source = Sop.box ~label:"source" ~size:(Vec3.create 1. 1. 1.) () in
  let middle = Sop.null ~label:"middle" source in
  let output = Sop.null ~label:"output" middle in
  let document = Edit_graph.of_graph output in
  check (Edit_graph.node_slot_names document ~node_id:(Node.id middle) = Some ["in0"]
      && Edit_graph.node_slot_names document ~node_id:(-1) = None)
    "editable entry did not expose canonical slots or reject a missing node";
  check (Edit_graph.replace_node middle document |> get == document
      && fst (Edit_graph.apply_parameters document ~node_id:(Node.id middle) [] |> get) == document)
    "unchanged parameter writes rebuilt the editable graph";
  check (Edit_graph.root document = Some (Node.id output)
      && List.length (Edit_graph.inspect document) = 3)
    "editable graph did not import the compiled DAG";
  let inner = Edit_graph.subgraph [Node.id source; Node.id middle] document in
  check (List.map (fun (info : Edit_graph.node_info) -> info.id)
      (Edit_graph.inspect inner) = [Node.id source; Node.id middle]
      && Edit_graph.inputs inner ~node_id:(Node.id middle) =
        Some [|Some (Node.id source)|]
      && Node.id (Edit_graph.compile inner |> get) = Node.id middle)
    "compound subgraph did not retain selected ids and their internal wire";
  let cut = Edit_graph.subgraph [Node.id middle] document in
  check (Edit_graph.inputs cut ~node_id:(Node.id middle) = Some [|None|]
      && Result.is_error (Edit_graph.compile cut))
    "compound subgraph retained a wire from outside its selection";
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
  let compiled = Edit_graph.compile_all reconnected in
  let node compiled id = Edit_graph.compiled_node compiled ~node_id:id |> get in
  let again = Edit_graph.compile_all ~previous:compiled reconnected in
  check (node again (Node.id output) == node compiled (Node.id output)
      && Node.id (node again (Node.id output))
         = Node.id (Edit_graph.compile reconnected |> get))
    "incremental compile rebuilt an unchanged document";
  let rewired = Edit_graph.disconnect ~consumer:(Node.id middle) ~input_index:0
      reconnected |> get in
  check (Result.is_error (Edit_graph.compiled_node
      (Edit_graph.compile_all ~previous:compiled rewired) ~node_id:(Node.id output)))
    "incremental compile reused a node across a disconnected input";
  let rewired = Edit_graph.connect ~source:(Node.id source)
      ~consumer:(Node.id middle) ~input_index:0 rewired |> get in
  let recompiled = Edit_graph.compile_all ~previous:compiled rewired in
  check (node recompiled (Node.id source) == node compiled (Node.id source)
      && Node.id (node recompiled (Node.id output)) = Node.id output)
    "incremental compile did not reuse the unchanged upstream node";
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
  check (Edit_graph.factory_slot_names null_factory = ["in0"])
    "unnamed factory inputs did not use canonical port names";
  let loose_null = Edit_graph.instantiate_optional null_factory [None] |> get in
  let loose_document = Edit_graph.add_node ~inputs:[|None|] loose_null document
      |> get in
  check (Edit_graph.inputs loose_document ~node_id:(Node.id loose_null)
      = Some [|None|])
    "factory could not create a node with a disconnected input";
  let match_size_factory = Edit_graph.factory_slots ~key:"match_size"
      ~slots:["input"; "target"]
      ~label:"Match Size" ~category:["Modify"]
      ~inputs:[Edit_graph.Required; Optional] (function
        | [Some input; target] -> Sop.match_size ?target input
        | _ -> invalid_arg "Match Size requires its geometry input") in
  check (Edit_graph.factory_slot_names match_size_factory = ["input"; "target"])
    "optional factory did not retain named input slots";
  List.iter (fun slots ->
    match Edit_graph.factory ~slots ~key:"invalid" ~label:"Invalid"
        ~category:["Test"] ~arity:1 (fun _ -> source) with
    | _ -> fail "factory accepted missing or blank slot names"
    | exception Invalid_argument _ -> ()) [[]; [""]; ["a"; "a"]];
  let loose_match = Edit_graph.instantiate_optional match_size_factory
      [None; None] |> get in
  let optional_document = Edit_graph.add_node ~factory:match_size_factory
      ~inputs:[|None; None|] loose_match document |> get
    |> Edit_graph.connect ~source:(Node.id source)
         ~consumer:(Node.id loose_match) ~input_index:0 |> get in
  let without_target = Edit_graph.compile_node optional_document
      ~node_id:(Node.id loose_match) |> get in
  check (Edit_graph.node_slot_names optional_document ~node_id:(Node.id loose_match)
      = Some ["input"; "target"])
    "editable entry lost its factory's named slots";
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
  (* a rest slot grows by connecting one past its last input *)
  let rest_factory = Edit_graph.factory_slots ~key:"merge" ~label:"Merge"
      ~slots:["input"] ~category:["Test"] ~inputs:[Edit_graph.Rest]
      (fun inputs -> Sop.merge (List.filter_map Fun.id inputs)) in
  check (Result.is_error (Edit_graph.instantiate_optional rest_factory [])
      && Result.is_ok (Edit_graph.instantiate_optional rest_factory [Some source; None; Some middle])
      && (try ignore (Edit_graph.factory_slots ~key:"bad" ~label:"Bad" ~category:["T"]
            ~inputs:[Edit_graph.Rest; Required] (fun _ -> source)); false
          with Invalid_argument _ -> true))
    "rest slot arity or position was not validated";
  let rest_node = Edit_graph.instantiate_optional rest_factory [Some source] |> get in
  let rest_document = Edit_graph.add_node ~factory:rest_factory ~inputs:[|None|]
      rest_node document |> get in
  let grow index source_node d = Edit_graph.connect ~source:(Node.id source_node)
      ~consumer:(Node.id rest_node) ~input_index:index d in
  let rest_document = grow 0 source rest_document |> get |> grow 1 middle |> get
    |> grow 2 source |> get in
  check (Edit_graph.node_slot_names rest_document ~node_id:(Node.id rest_node)
      = Some ["input"; "input_2"; "input_3"]
      && Result.is_error (grow 4 source rest_document)
      && List.length (Node.inputs (Edit_graph.compile_node rest_document
           ~node_id:(Node.id rest_node) |> get)) = 3)
    "rest slot did not grow, name its extras or rebuild through the factory";
  let rest_document = Edit_graph.disconnect ~consumer:(Node.id rest_node)
      ~input_index:1 rest_document |> get in
  check (List.length (Node.inputs (Edit_graph.compile_node rest_document
      ~node_id:(Node.id rest_node) |> get)) = 2)
    "a disconnected rest input was not skipped";
  let optional_factory slots = Edit_graph.factory_slots ~key:"optional_null"
    ~operation:"null" ~slots ~label:"Optional Null"
    ~category:["Test"]
    ~inputs:(List.map (fun _ -> Edit_graph.Optional) slots)
    (fun _ -> Sop.null source) in
  let wide = optional_factory ["a"; "b"]
  and narrow = optional_factory ["b"] in
  let optional_node = Edit_graph.instantiate_optional wide [None; None]
    |> get in
  let optional_graph = Edit_graph.add_node ~factory:wide
    ~inputs:[|None; None|] optional_node document |> get
    |> Edit_graph.connect ~source:(Node.id source)
         ~consumer:(Node.id optional_node) ~input_index:1 |> get in
  let narrowed = Edit_graph.rebind_factory ~preserve_wires_by_name:true
    ~node_id:(Node.id optional_node) narrow optional_graph |> get in
  check (Edit_graph.node_slot_names narrowed ~node_id:(Node.id optional_node)
      = Some ["b"]
    && Edit_graph.inputs narrowed ~node_id:(Node.id optional_node)
       = Some [|Some (Node.id source)|])
    "factory resize lost a wire on a retained named slot";
  let occupied = Edit_graph.connect ~source:(Node.id source)
    ~consumer:(Node.id optional_node) ~input_index:0 optional_graph |> get in
  check (Result.is_error (Edit_graph.rebind_factory
    ~preserve_wires_by_name:true ~node_id:(Node.id optional_node)
    narrow occupied))
    "factory resize removed a connected slot";
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
  let fixed_source = Node.Private.fresh_id () + 1000 in
  let fixed_middle = fixed_source + 1 in
  let fixed, mapping = Edit_graph.paste
      ~ids:[Node.id source, fixed_source; Node.id middle, fixed_middle]
      fragment reconnected |> get in
  check (mapping = [Node.id source, fixed_source; Node.id middle, fixed_middle]
      && Edit_graph.inputs fixed ~node_id:fixed_middle = Some [|Some fixed_source|]
      && Node.id (Edit_graph.compile_node fixed ~node_id:fixed_middle |> get)
        = fixed_middle)
    "compound paste did not preserve assigned compiled ids";
  check (Result.is_error (Edit_graph.paste ~ids:[Node.id source, Node.id middle;
      Node.id middle, Node.id source] fragment reconnected))
    "compound paste overwrote existing node ids";
  let external_fragment = Edit_graph.copy_nodes [Node.id middle] reconnected
      |> get in
  let pasted, mapping = Edit_graph.paste external_fragment reconnected |> get in
  check (Edit_graph.inputs pasted ~node_id:(List.assoc (Node.id middle) mapping)
      = Some [|None|])
    "subgraph paste retained an external connection instead of a loose slot";
  let merged = Sop.merge [source; middle] in
  let loose = Edit_graph.of_graph merged
    |> Edit_graph.disconnect ~consumer:(Node.id merged) ~input_index:1 |> get in
  let bypassed = Edit_graph.set_bypass loose ~node_id:(Node.id merged) true |> get in
  check (Edit_graph.compile bypassed |> get == source
      && Edit_graph.set_bypass bypassed ~node_id:(Node.id merged) true |> get == bypassed
      && Result.is_error (Edit_graph.compile
        (Edit_graph.set_bypass bypassed ~node_id:(Node.id merged) false |> get)))
    "bypass did not ignore secondary slots or restore the stored operation";
  let copied = Edit_graph.copy_nodes [Node.id merged] bypassed |> get in
  let copy, mapping = Edit_graph.paste copied bypassed |> get in
  check ((List.find (fun (info : Edit_graph.node_info) ->
    info.id = List.assoc (Node.id merged) mapping) (Edit_graph.inspect copy)).bypass)
    "copy dropped bypass metadata";
  let targets = Sop.points [|0., 0., 0.; 2., 0., 0.; 4., 0., 0.|] in
  let packed = Sop.copy_to_points ~pack:true ~source ~targets () in
  let packed_consumer = Sop.null packed in
  let packed_doc = Edit_graph.of_graph packed_consumer
    |> fun doc -> Edit_graph.set_bypass doc ~node_id:(Node.id packed_consumer) true |> get in
  let session = Session.create ~max_entries:16 ~max_payload_bytes:1048576 |> get in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let cook doc = match Session.cook session ~context:(Context.create () |> get)
        (Edit_graph.compile doc |> get) with
      | Ok output -> output | Error error -> fail (Diagnostic.error_to_string error) in
    let output = cook packed_doc in
    check (Option.map Array.length output.instances = Some 3
        && output.geometry == (cook (Edit_graph.of_graph source)).geometry)
      "bypass materialized packed instances";
    let empty = Edit_graph.of_graph source
      |> fun doc -> Edit_graph.set_bypass doc ~node_id:(Node.id source) true |> get in
    check (Pdk.Geometry.point_count (cook empty).geometry = 0)
      "bypassed source did not produce empty geometry");
  let branch = Sop.merge [middle; output] in
  let dissolved = Edit_graph.dissolve_nodes [Node.id middle; Node.id output]
      (Edit_graph.of_graph branch) in
  check (Edit_graph.inputs dissolved ~node_id:(Node.id branch)
      = Some [|Some (Node.id source); Some (Node.id source)|]
      && Result.is_ok (Edit_graph.compile dissolved)
      && Edit_graph.root (Edit_graph.dissolve_nodes [Node.id middle; Node.id output]
          reconnected) = Some (Node.id source))
    "dissolve did not reconnect selected chains to every consumer and the root";
  print_endline "editable graph tests passed"
