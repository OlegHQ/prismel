open Prismel
open Procedural

module Preset = Prismel_editor.Private.Preset
module Document = Prismel_editor.Private.Document

let check condition message = if not condition then failwith message
let key k = Event.KeyPressed k
let char c = key (Input.KeyChar c)

let frame ?(keys = []) ?(mouse = (450., 320.)) events count : Frame.t = {
  width = 900; height = 640; size = 900, 640;
  drawable_width = 900; drawable_height = 640; drawable_size = 900, 640;
  pixel_scale = 1., 1.; time = float count /. 60.; dt = 1. /. 60.;
  fps = 60.; count; mouse; mouse_delta = 0., 0.; keys; mouse_buttons = []; events }

module Param = Editor_core.Param

type fixture = { doc : Editor_document.Document.t }

(* A node with a fixed id, as the tests below address them. *)
let restored id label factory =
  let arity = Edit_graph.factory_arity factory in
  let node = Edit_graph.instantiate_optional factory (List.init arity (fun _ -> None))
    |> Result.get_ok |> Node.relabel label in
  Node.Private.restore_id id node |> Result.get_ok

(* text of a document dump: a drive line and a value literal *)
let dump_lines text = String.split_on_char '\n' text
let drive_of dump ~node ~path =
  let prefix = Printf.sprintf "  drive %d.%s " node path in
  List.find_map (fun line ->
    if String.starts_with ~prefix line
    then Some (String.sub line (String.length prefix) (String.length line - String.length prefix))
    else None) (dump_lines dump)
let value_literal dump ~node ~name =
  let prefix = Printf.sprintf "  value %d " node in
  List.find_map (fun line ->
    if String.starts_with ~prefix line then
      List.find_map (fun word ->
        let key = name ^ "=" in
        if String.starts_with ~prefix:key word
        then Some (float_of_string (String.sub word (String.length key) (String.length word - String.length key)))
        else None) (String.split_on_char ' ' line)
    else None) (dump_lines dump)

let run () =
  let directory = Filename.temp_dir "prismel-document-contract" "" in
  Fun.protect ~finally:(fun () ->
    Array.iter (fun name -> Sys.remove (Filename.concat directory name)) (Sys.readdir directory);
    Unix.rmdir directory) (fun () ->
  let code = Sop.points [||] in
  let factories = Sop_catalog.Editor.factories in
  let factory key = List.find (fun f -> Edit_graph.factory_key f = key) factories in
  (* The editable document the tests below start from: one geometry object
     (id 10) owning a SOP network with one box (id 20). *)
  let scene_graph = Edit_graph.add_node ~factory:Editor_document.Objects.Geometry.factory
    ~inputs:[|None|] (restored 10 "geo1" Editor_document.Objects.Geometry.factory) Edit_graph.empty
    |> Result.get_ok in
  let box_graph = Edit_graph.add_node ~factory:(factory "box") ~inputs:[||]
    (restored 20 "box" (factory "box")) Edit_graph.empty |> Result.get_ok
    |> Edit_graph.set_root 20 |> Result.get_ok in
  let valid = { Editor_document.Document.
    scene = Editor_document.Document.of_geometry ~context:Flow.Context.Scene scene_graph (Some 10);
    networks = Editor_document.Document.Layout.singleton 10
      (Editor_document.Document.of_geometry ~context:Flow.Context.Sop box_graph (Some 20));
    definitions = Editor_document.Document.String_map.empty;
    compiled_ids = Flow_sop.Instance_path.Map.empty;
    active_camera = None; settings = Editor_document.Settings.none; workspace = None } in
  check (Result.is_ok (Editor_document.Document.validate valid)) "the fixture document is valid";
  let direct = { doc = valid } in
  (* Value nodes and drives: a clock feeds a sine that drives the box's
     size, and one component of its center is an expression. *)
  let overlay =
    let graph, _ = Option.get (Editor_document.Document.object_network valid 10) in
    let graph, math = Flow_sop.Network.add_value_node ~label:"Sine" Flow.Value_kind.Math graph
      |> Result.get_ok in
    let graph, clock = Flow_sop.Network.add_value_node ~label:"Clock" Flow.Value_kind.Time graph
      |> Result.get_ok in
    let graph, _ = Flow_sop.Network.apply_value_parameters graph ~node_id:clock
      [ "speed", Param.Float_value 2.25 ] |> Result.get_ok in
    let graph, _ = Flow_sop.Network.apply_value_parameters graph ~node_id:math
      [ "op", Param.Choice_value "sin" ] |> Result.get_ok in
    let connect graph source target = Flow_sop.Network.connect_value ~source ~target graph |> Result.get_ok in
    let graph = connect graph Flow_sop.Port.{node = clock; path = "t"} Flow_sop.Port.{node = math; path = "a"} in
    let graph = connect graph Flow_sop.Port.{node = math; path = "out"} Flow_sop.Port.{node = 20; path = "size"} in
    let graph = Flow_sop.Network.set_expr ~target:Flow_sop.Port.{node = 20; path = "center.x"}
      (Flow.Expr.parse "sin(t * 0.6)" |> Result.get_ok) graph |> Result.get_ok in
    graph in
  let node_named label = (List.find (fun (n : Flow.Graph.node) -> n.label = label)
    (Flow.Graph.inspect overlay.values)).id in
  let clock_id = node_named "Clock" and math_id = node_named "Sine" in
  check (List.length (Flow.Graph.inspect overlay.values) = 2
    && Flow_sop.Port.Map.cardinal overlay.drives = 3)
    "the fixture lost value nodes or drives";
  let renamed_value = Flow_sop.Network.relabel ~node_id:clock_id "Seconds" overlay
    |> Result.get_ok in
  let renamed_box = Flow_sop.Network.relabel ~node_id:20 "Scaled box" renamed_value
    |> Result.get_ok in
  check ((Flow.Graph.find renamed_box.values ~node_id:clock_id |> Option.get).label = "Seconds"
    && (Edit_graph.find renamed_box.geometry ~node_id:20 |> Option.get
      |> Node.label) = "Scaled box"
    && renamed_box.drives == overlay.drives)
    "Flow rename changed topology or failed to update one node kind";
  check (Flow_sop.Network.relabel ~node_id:clock_id "" renamed_box
    |> Result.get_ok == renamed_box) "blank rename changed the network";
  let clock = Flow.Graph.find overlay.values ~node_id:clock_id |> Option.get in
  check (List.exists (fun (field : Param.field_view) ->
    field.name = "speed" && field.current = Param.Float_value 2.25)
    (Flow.Value_kind.fields clock.parameters))
    "a value-node literal changed";
  let expr = match Flow_sop.Port.Map.find_opt
      {Flow_sop.Port.node = 20; path = "center.x"} overlay.drives with
    | Some (Flow_sop.Drive.Expr expr) -> expr
    | _ -> failwith "the fixture lost its expression drive" in
  check (abs_float ((Flow.Expr.eval ~time:1. expr |> Result.get_ok) -. sin 0.6) < 1e-12)
    "an expression changed";
  let module Canvas = Editor_core.Network_layout in
  let pane_layout = { Canvas.empty with at = Canvas.Int_map.singleton clock_id (-228., 48.);
    bends = Canvas.Port_map.singleton (math_id, "a") [12., 24.] } in
  let pane = Pxui_graph.create_document overlay |> Pxui_graph.with_layout pane_layout in
  let tile id = List.find (fun (tile : Pxui_graph.node_view) -> tile.id = id)
      (Pxui_graph.node_views pane) in
  check ((tile clock_id).depth < (tile math_id).depth && (tile math_id).depth < (tile 20).depth)
    "value wires did not determine left-to-right canvas depth";
  check (Pxui_graph.selected (Pxui_graph.select clock_id pane) = Some clock_id)
    "value tile cannot be selected";
  check (Canvas.Int_map.find_opt clock_id (Pxui_graph.layout pane).at = Some (-228., 48.))
    "canvas erased a saved value position";
  let another_box = Sop_catalog.Box.create () in
  let expanded_geometry = Edit_graph.add_node ~factory:(List.find (fun factory ->
    Edit_graph.factory_key factory = "box") factories) another_box overlay.geometry
    |> Result.get_ok in
  let changed = Flow_sop.Network.with_geometry expanded_geometry overlay |> Result.get_ok in
  let pane = Pxui_graph.with_document changed pane in
  check (Canvas.Port_map.mem (math_id, "a") (Pxui_graph.layout pane).bends)
    "geometry edit erased a value wire bend";
  let copied, _ = Pxui_graph.run_command
    (Pxui_graph.select 20 (Pxui_graph.create_document overlay)) Pxui_graph.Copy in
  let _, pasted = Pxui_graph.run_command copied Pxui_graph.Paste in
  let fragment = match pasted with [Pxui_graph.Paste_requested request] -> request.fragment
    | _ -> failwith "graph clipboard lost the Flow fragment" in
  let pasted, mapping = Flow_sop.Network.paste fragment overlay |> Result.get_ok in
  let copied_box = List.assoc 20 mapping in
  check (Flow_sop.Port.Map.mem {Flow_sop.Port.node = copied_box; path = "center.x"} pasted.drives
    && not (Flow_sop.Port.Map.mem {Flow_sop.Port.node = copied_box; path = "size"} pasted.drives))
    "copy/paste lost an expression or retained an external value wire";
  let grouped, grouped_id = match Editor_document.Document.group direct.doc
      (Editor_document.Document.Inside 10) ~selected:[20]
      ~positions:[20, 48., 24.] with
    | Ok value -> value
    | Error diagnostic -> failwith (Flow.Diagnostic.to_string diagnostic) in
  let grouped_definition = Editor_document.Document.String_map.find
    "compound_1" grouped.definitions in
  check (Result.is_ok (Editor_document.Document.validate grouped)
    && grouped_id <> 20
    && Flow_sop.Network.Int_map.mem grouped_id
      (Editor_document.Document.Layout.find 10 grouped.networks).graph.instances
    && Edit_graph.find grouped_definition.spec.body.geometry ~node_id:20 <> None)
    "group did not move the selected node into a valid shared definition";
  let level = Editor_document.Document.Inside 10 in
  let source_network = Editor_document.Document.network direct.doc level
    |> Option.get in
  let graph, inner_value = Flow_sop.Network.add_value_node
    Flow.Value_kind.Value source_network.graph |> Result.get_ok in
  let graph, outer_value = Flow_sop.Network.add_value_node
    Flow.Value_kind.Value graph |> Result.get_ok in
  let graph = Flow_sop.Network.set_literal
    ~target:Flow_sop.Port.{node = outer_value; path = "v"}
    (Flow_sop.Port.Scalar (Param.Float_value 2.)) graph |> Result.get_ok in
  let graph = Flow_sop.Network.connect_value
    ~source:Flow_sop.Port.{node = outer_value; path = "out"}
    ~target:Flow_sop.Port.{node = inner_value; path = "v"} graph
    |> Result.get_ok in
  let graph = Flow_sop.Network.connect_value
    ~source:Flow_sop.Port.{node = inner_value; path = "out"}
    ~target:Flow_sop.Port.{node = 20; path = "uniform_scale"} graph
    |> Result.get_ok in
  let value_doc = Editor_document.Document.with_network direct.doc level
    {source_network with graph} in
  let value_grouped, value_instance = Editor_document.Document.group
    value_doc level ~selected:[20; inner_value]
    ~positions:[20, 48., 24.; inner_value, 0., 24.] |> Result.get_ok in
  let value_inside = Editor_document.Document.enter_compound
    value_grouped level value_instance |> Option.get in
  let value_body = Editor_document.Document.network value_grouped
    value_inside |> Option.get in
  check (Result.is_ok (Editor_document.Document.validate value_grouped)
    && Flow.Graph.find value_body.graph.values ~node_id:inner_value <> None
    && Editor_document.Document.parent_level value_inside
       = Some (level, value_instance))
    "value-aware document group is invalid";
  let value_ungrouped, value_mapping = Editor_document.Document.ungroup
    value_grouped level ~instance_id:value_instance
    |> Result.get_ok in
  let restored = Editor_document.Document.network value_ungrouped level
    |> Option.get in
  let restored_value = List.assoc inner_value value_mapping
  and restored_sop = List.assoc 20 value_mapping in
  check (Result.is_ok (Editor_document.Document.validate value_ungrouped)
    && Flow_sop.Network.Int_map.mem value_instance
      restored.graph.instances = false
    && Flow_sop.Port.Map.find
      Flow_sop.Port.{node = restored_value; path = "v"}
      restored.graph.drives
       = Flow_sop.Drive.Wire {node = outer_value; output = "out"}
    && Flow_sop.Port.Map.find
      Flow_sop.Port.{node = restored_sop; path = "uniform_scale"}
      restored.graph.drives
       = Flow_sop.Drive.Wire {node = restored_value; output = "out"})
    "value-aware group failed ungroup round trip";
  let bare_graph, bare_value = Flow_sop.Network.add_value_node
    Flow.Value_kind.Value
    (Flow_sop.Network.of_geometry Edit_graph.empty) |> Result.get_ok in
  let bare_doc = Editor_document.Document.with_network direct.doc level
    {source_network with graph = bare_graph;
      layout = Editor_core.Network_layout.empty; displayed = None} in
  let bare_grouped, bare_instance = Editor_document.Document.group
    bare_doc level ~selected:[bare_value]
    ~positions:[bare_value, 0., 0.] |> Result.get_ok in
  let bare_network = Editor_document.Document.network bare_grouped level
    |> Option.get in
  check (bare_network.displayed = None
    && Result.is_ok (Editor_document.Document.validate bare_grouped)
    && Result.is_ok (Editor_document.Document.allocate_compiled_ids bare_grouped))
    "value-only compound required a geometry display";
  let bare_ungrouped, _ = Editor_document.Document.ungroup bare_grouped
    level ~instance_id:bare_instance |> Result.get_ok in
  check (Result.is_ok (Editor_document.Document.validate bare_ungrouped))
    "value-only compound failed ungroup";
  let root_level = Editor_document.Document.Inside 10 in
  let inside = Editor_document.Document.enter_compound grouped root_level
    grouped_id |> Option.get in
  let exported, exported_name = Editor_document.Document.export_parameter
    grouped inside ~target:Flow_sop.Port.{node = 20; path = "uniform_scale"}
    |> Result.get_ok in
  let exported_definition = Editor_document.Document.String_map.find
    "compound_1" exported.definitions in
  let exported_marker = Edit_graph.inspect exported_definition.spec.body.geometry
    |> List.find (fun (node : Edit_graph.node_info) ->
      node.operation = "flow_inputs") in
  let exported_parent = Editor_document.Document.network exported root_level
    |> Option.get in
  check (exported_name = "uniform_scale"
    && List.length exported_definition.spec.inputs = 1
    && Flow_sop.Port.Map.find
      Flow_sop.Port.{node = 20; path = "uniform_scale"}
      exported_definition.spec.body.drives
       = Flow_sop.Drive.Wire {node = exported_marker.id;
           output = "uniform_scale"}
    && Flow_sop.Port.literal (Flow_sop.Network.parameter
       exported_parent.graph Flow_sop.Port.{node = grouped_id;
         path = "uniform_scale"} |> Result.get_ok)
       = Flow_sop.Port.Scalar (Param.Float_value 1.)
    && Result.is_ok (Editor_document.Document.validate exported)
    && Result.is_ok (Editor_document.Document.allocate_compiled_ids exported))
    "export did not add one typed shared input and wire the original row";
  let exported_body = Editor_document.Document.network exported inside
    |> Option.get in
  let vector_body = Flow_sop.Network.set_literal
    ~target:Flow_sop.Port.{node = 20; path = "center"}
    (Flow_sop.Port.Vector (1., 2., 3.)) exported_body.graph
    |> Result.get_ok in
  let vector_doc = Editor_document.Document.with_network exported inside
    {exported_body with graph = vector_body} in
  let vector_exported, vector_name = Editor_document.Document.export_parameter
    vector_doc inside ~target:Flow_sop.Port.{node = 20; path = "center"}
    |> Result.get_ok in
  let vector_definition = Editor_document.Document.String_map.find
    "compound_1" vector_exported.definitions in
  let vector_port = List.find (fun
    (port : Flow_sop.Network.interface_port) -> port.name = vector_name)
    vector_definition.spec.inputs in
  let vector_parent = Editor_document.Document.network vector_exported
    root_level |> Option.get in
  check (vector_port.ty = Flow.Port_type.Vec3
    && vector_port.default = Some (Flow_sop.Port.Vector (1., 2., 3.))
    && Flow_sop.Port.literal (Flow_sop.Network.parameter
       vector_parent.graph Flow_sop.Port.{node = grouped_id;
         path = vector_name} |> Result.get_ok)
       = Flow_sop.Port.Vector (1., 2., 3.)
    && Result.is_ok (Editor_document.Document.validate vector_exported))
    "Vec3 export lost its nonuniform default";
  let invalid_vector = {vector_port with
    default = Some (Flow_sop.Port.Vector (nan, 2., 3.))} in
  let invalid_definition = {vector_definition with spec =
    {vector_definition.spec with inputs = List.map (fun
      (port : Flow_sop.Network.interface_port) ->
      if port.name = vector_name then invalid_vector else port)
      vector_definition.spec.inputs}} in
  let invalid_doc = {vector_exported with definitions =
    Editor_document.Document.String_map.add "compound_1"
      invalid_definition vector_exported.definitions} in
  check (Result.is_error (Editor_document.Document.validate invalid_doc))
    "nonfinite Vec3 interface default passed validation";
  let twice, _ = Editor_document.Document.export_parameter exported inside
    ~target:Flow_sop.Port.{node = 20; path = "consolidate_points"}
    |> Result.get_ok in
  let reordered_values = Editor_document.Document.reorder_interface twice
    ~definition_name:"compound_1" ~side:Input
    ~name:"consolidate_points" ~delta:(-1) |> Result.get_ok in
  let reordered_definition = Editor_document.Document.String_map.find
    "compound_1" reordered_values.definitions in
  check (List.map (fun (port : Flow_sop.Network.interface_port) -> port.name)
      reordered_definition.spec.inputs = ["consolidate_points"; "uniform_scale"]
    && Result.is_ok (Editor_document.Document.validate reordered_values)
    && Result.is_ok (Editor_document.Document.allocate_compiled_ids reordered_values))
    "value interface reorder lost named wires or factory metadata";
  let exported_graph = Flow_sop.Network.set_literal
    ~target:Flow_sop.Port.{node = grouped_id; path = "uniform_scale"}
    (Flow_sop.Port.Scalar (Param.Float_value 2.)) exported_parent.graph
    |> Result.get_ok in
  let exported = Editor_document.Document.with_network exported root_level
    {exported_parent with graph = exported_graph} in
  let renamed = Editor_document.Document.rename_interface_port exported
    ~definition_name:"compound_1" ~side:Input
    ~from:"uniform_scale" ~into:"scale" |> Result.get_ok in
  let renamed_definition = Editor_document.Document.String_map.find
    "compound_1" renamed.definitions in
  let renamed_parent = Editor_document.Document.network renamed root_level
    |> Option.get in
  check (Flow_sop.Port.Map.find
      Flow_sop.Port.{node = 20; path = "uniform_scale"}
      renamed_definition.spec.body.drives
       = Flow_sop.Drive.Wire {node = exported_marker.id; output = "scale"}
    && Flow_sop.Network.String_map.find "scale"
       (Flow_sop.Network.Int_map.find grouped_id
         renamed_parent.graph.instances).literals = Param.Float_value 2.
    && Result.is_ok (Editor_document.Document.validate renamed)
    && Result.is_ok (Editor_document.Document.allocate_compiled_ids renamed))
    "renaming a value input lost its body wire or instance literal";
  check (Result.is_error (Editor_document.Document.unexport_port renamed
    ~definition_name:"compound_1" ~side:Input ~name:"scale"))
    "unexport discarded an instance literal override";
  let graph = Flow_sop.Network.set_literal
    ~target:Flow_sop.Port.{node = grouped_id; path = "scale"}
    (Flow_sop.Port.Scalar (Param.Float_value 1.)) renamed_parent.graph
    |> Result.get_ok in
  let layout = {renamed_parent.layout with rows =
    Editor_core.Network_layout.Int_map.add grouped_id
      (Editor_core.Network_layout.String_map.singleton "scale" true)
      renamed_parent.layout.rows} in
  let reset = Editor_document.Document.with_network renamed root_level
    {renamed_parent with graph; layout} in
  let unexported = Editor_document.Document.unexport_port reset
    ~definition_name:"compound_1" ~side:Input ~name:"scale"
    |> Result.get_ok in
  let unexported_definition = Editor_document.Document.String_map.find
    "compound_1" unexported.definitions in
  let unexported_parent = Editor_document.Document.network unexported root_level
    |> Option.get in
  check (unexported_definition.spec.inputs = []
    && Flow_sop.Port.Map.is_empty unexported_definition.spec.body.drives
    && Flow_sop.Network.String_map.is_empty
       (Flow_sop.Network.Int_map.find grouped_id
         unexported_parent.graph.instances).literals
    && (match Editor_core.Network_layout.Int_map.find_opt grouped_id
        unexported_parent.layout.rows with
        | None -> true
        | Some rows -> not (Editor_core.Network_layout.String_map.mem
            "scale" rows))
    && Result.is_ok (Editor_document.Document.validate unexported)
    && Result.is_ok (Editor_document.Document.allocate_compiled_ids unexported))
    "unexport did not remove the unused shared value input";
  let parent = Editor_document.Document.network grouped root_level
    |> Option.get in
  let fragment = Flow_sop.Network.copy_nodes [grouped_id] parent.graph
    |> Result.get_ok in
  let graph, duplicated = Flow_sop.Network.paste fragment parent.graph
    |> Result.get_ok in
  let duplicate_id = List.assoc grouped_id duplicated in
  let shared = Editor_document.Document.with_network grouped root_level
    {parent with graph} in
  let unique, unique_name = Editor_document.Document.make_unique shared
    root_level ~instance_id:grouped_id |> Result.get_ok in
  let unique_parent = Editor_document.Document.network unique root_level
    |> Option.get in
  let unique_instance = Flow_sop.Network.Int_map.find grouped_id
    unique_parent.graph.instances in
  let shared_instance = Flow_sop.Network.Int_map.find duplicate_id
    unique_parent.graph.instances in
  let unique_definition = Editor_document.Document.String_map.find unique_name
    unique.definitions in
  check (unique_name = "compound_1_2"
    && unique_instance.definition = unique_name
    && shared_instance.definition = "compound_1"
    && Edit_graph.find unique_definition.spec.body.geometry ~node_id:20 = None
    && Result.is_ok (Editor_document.Document.validate unique))
    "make unique did not detach one instance with fresh definition ids";
  let unique_inside = Editor_document.Document.enter_compound unique root_level
    grouped_id |> Option.get in
  let copied_box = Edit_graph.inspect unique_definition.spec.body.geometry
    |> List.find (fun (node : Edit_graph.node_info) -> node.operation = "box") in
  let unique_body = Editor_document.Document.network unique unique_inside
    |> Option.get in
  let changed = Flow_sop.Network.relabel ~node_id:copied_box.id
    "Unique box" unique_body.graph |> Result.get_ok in
  let unique = Editor_document.Document.with_network unique unique_inside
    {unique_body with graph = changed} in
  check (Node.label (Edit_graph.find
      (Editor_document.Document.String_map.find "compound_1"
        unique.definitions).spec.body.geometry ~node_id:20 |> Option.get)
      <> "Unique box"
    && Result.is_ok (Editor_document.Document.validate unique))
    "editing a unique definition also changed the shared definition";
  check (Result.is_ok (Editor_document.Document.allocate_compiled_ids unique))
    "make unique did not flatten both detached and shared instances";
  let source_network = Editor_document.Document.network direct.doc root_level
    |> Option.get in
  let source_box = Edit_graph.find source_network.graph.geometry ~node_id:20
    |> Option.get in
  let null_factory = List.find (fun factory ->
    Edit_graph.factory_key factory = "null") factories in
  let middle = Edit_graph.instantiate null_factory [source_box]
    |> Result.get_ok in
  let downstream = Edit_graph.instantiate null_factory [middle]
    |> Result.get_ok in
  let middle_id = Node.id middle and downstream_id = Node.id downstream in
  let renamed_geometry = source_network.graph.geometry
    |> Edit_graph.add_node ~factory:null_factory middle |> Result.get_ok
    |> Edit_graph.add_node ~factory:null_factory downstream |> Result.get_ok
    |> Edit_graph.set_root downstream_id |> Result.get_ok in
  let graph = Flow_sop.Network.with_geometry renamed_geometry source_network.graph
    |> Result.get_ok in
  let wired = Editor_document.Document.with_network direct.doc root_level
    {source_network with graph; displayed = Some downstream_id} in
  let wired, wired_instance = Editor_document.Document.group wired root_level
    ~selected:[middle_id] ~positions:[middle_id, 48., 24.]
    |> Result.get_ok in
  let parent = Editor_document.Document.network wired root_level |> Option.get in
  let fragment = Flow_sop.Network.copy_nodes [wired_instance] parent.graph
    |> Result.get_ok in
  let graph, mapping = Flow_sop.Network.paste fragment parent.graph
    |> Result.get_ok in
  let second_instance = List.assoc wired_instance mapping in
  let layout = {parent.layout with bends =
    Editor_core.Network_layout.Port_map.add (wired_instance, "in0")
      [12., 24.] parent.layout.bends} in
  let wired = Editor_document.Document.with_network wired root_level
    {parent with graph; layout} in
  let wired = Editor_document.Document.rename_interface_port wired
    ~definition_name:"compound_1" ~side:Input ~from:"in0" ~into:"entry"
    |> Result.get_ok in
  let wired = Editor_document.Document.rename_interface_port wired
    ~definition_name:"compound_1" ~side:Output ~from:"result" ~into:"mesh"
    |> Result.get_ok in
  let wired_parent = Editor_document.Document.network wired root_level
    |> Option.get in
  let renamed_definition = Editor_document.Document.String_map.find
    "compound_1" wired.definitions in
  let inputs_id = Edit_graph.inspect renamed_definition.spec.body.geometry
    |> List.find (fun (node : Edit_graph.node_info) ->
      node.operation = "flow_inputs") |> fun node -> node.id in
  check (Flow_sop.Network.geometry_source wired_parent.graph
      Flow_sop.Port.{node = wired_instance; path = "entry"}
        = Some Flow_sop.Port.{node = 20; path = "geo"}
    && Flow_sop.Network.geometry_source wired_parent.graph
      Flow_sop.Port.{node = downstream_id; path = "in0"}
        = Some Flow_sop.Port.{node = wired_instance; path = "mesh"}
    && Flow_sop.Network.geometry_source renamed_definition.spec.body
      Flow_sop.Port.{node = middle_id; path = "in0"}
        = Some Flow_sop.Port.{node = inputs_id; path = "entry"}
    && Edit_graph.node_slot_names wired_parent.graph.geometry
      ~node_id:second_instance = Some ["entry"]
    && Editor_core.Network_layout.Port_map.find_opt
      (wired_instance, "entry") wired_parent.layout.bends = Some [12., 24.]
    && Editor_core.Network_layout.Port_map.find_opt
      (wired_instance, "in0") wired_parent.layout.bends = None
    && Result.is_ok (Editor_document.Document.validate wired)
    && Result.is_ok (Editor_document.Document.allocate_compiled_ids wired))
    "renaming shared geometry interface ports lost a wire or cook path";
  check (Result.is_error (Editor_document.Document.rename_interface_port wired
      ~definition_name:"compound_1" ~side:Input ~from:"entry"
      ~into:"1bad")
    && (match Editor_document.Document.rename_interface_port wired
        ~definition_name:"compound_1" ~side:Output ~from:"mesh"
        ~into:"mesh" with Ok same -> same == wired | Error _ -> false))
    "interface rename accepted an invalid name or changed an unchanged port";
  let source2 = Sop.points [|4., 5., 6.|] in
  let inner1 = Sop.null source_box and inner2 = Sop.null source2 in
  let outer1 = Sop.null inner1 and outer2 = Sop.null inner2 in
  let parent = Editor_document.Document.network direct.doc root_level
    |> Option.get in
  let reorder_geometry = parent.graph.geometry
    |> Edit_graph.add_node source2 |> Result.get_ok
    |> Edit_graph.add_node inner1 |> Result.get_ok
    |> Edit_graph.add_node inner2 |> Result.get_ok
    |> Edit_graph.add_node outer1 |> Result.get_ok
    |> Edit_graph.add_node outer2 |> Result.get_ok
    |> Edit_graph.set_root (Node.id outer1) |> Result.get_ok in
  let graph = Flow_sop.Network.with_geometry reorder_geometry parent.graph
    |> Result.get_ok in
  let reorder_source = Editor_document.Document.with_network direct.doc
    root_level {parent with graph; displayed = Some (Node.id outer1)} in
  let reorder_source, reorder_instance = Editor_document.Document.group
    reorder_source root_level
    ~selected:[Node.id inner1; Node.id inner2]
    ~positions:[Node.id inner1, 48., 24.; Node.id inner2, 48., 72.]
    |> Result.get_ok in
  let reorder_definition = Editor_document.Document.String_map.find
    "compound_1" reorder_source.definitions in
  let input_names = List.map (fun (port : Flow_sop.Network.interface_port) ->
    port.name) reorder_definition.spec.inputs
  and output_names = List.map (fun (port : Flow_sop.Network.interface_port) ->
    port.name) reorder_definition.spec.outputs in
  check (List.length input_names = 2 && List.length output_names = 2)
    "two-boundary reorder fixture has the wrong interface";
  let before_parent = Editor_document.Document.network reorder_source root_level
    |> Option.get in
  let input_sources = List.map (fun name ->
    Flow_sop.Network.geometry_source before_parent.graph
      Flow_sop.Port.{node = reorder_instance; path = name}) input_names in
  let output_sources = List.map (fun id ->
    Flow_sop.Network.geometry_source before_parent.graph
      Flow_sop.Port.{node = id; path = "in0"})
      [Node.id outer1; Node.id outer2] in
  let reordered = Editor_document.Document.reorder_interface reorder_source
    ~definition_name:"compound_1" ~side:Input
    ~name:(List.hd input_names) ~delta:1 |> Result.get_ok in
  let reordered = Editor_document.Document.reorder_interface reordered
    ~definition_name:"compound_1" ~side:Output
    ~name:(List.hd output_names) ~delta:1 |> Result.get_ok in
  let reordered_parent = Editor_document.Document.network reordered root_level
    |> Option.get in
  let reordered_definition = Editor_document.Document.String_map.find
    "compound_1" reordered.definitions in
  let outputs_marker = Edit_graph.inspect reordered_definition.spec.body.geometry
    |> List.find (fun (node : Edit_graph.node_info) ->
      node.operation = "flow_outputs") in
  check (Edit_graph.node_slot_names reordered_parent.graph.geometry
      ~node_id:reorder_instance = Some (List.rev input_names)
    && Edit_graph.node_slot_names reordered_definition.spec.body.geometry
      ~node_id:outputs_marker.id = Some (List.rev output_names)
    && List.map (fun name -> Flow_sop.Network.geometry_source
      reordered_parent.graph Flow_sop.Port.{node = reorder_instance; path = name})
      input_names = input_sources
    && List.map (fun id -> Flow_sop.Network.geometry_source
      reordered_parent.graph Flow_sop.Port.{node = id; path = "in0"})
      [Node.id outer1; Node.id outer2] = output_sources
    && Result.is_ok (Editor_document.Document.validate reordered)
    && Result.is_ok (Editor_document.Document.allocate_compiled_ids reordered))
    "reordering geometry interface ports swapped or dropped sources";
  let removable_input = Flow_sop.Network.geometry_source
    reordered_definition.spec.body
    Flow_sop.Port.{node = Node.id inner2; path = "in0"}
    |> Option.get |> fun source -> source.path in
  let removable_output = Flow_sop.Network.geometry_source
    reordered_parent.graph
    Flow_sop.Port.{node = Node.id outer2; path = "in0"}
    |> Option.get |> fun source -> source.path in
  check (Result.is_error (Editor_document.Document.unexport_port reordered
      ~definition_name:"compound_1" ~side:Input ~name:removable_input)
    && Result.is_error (Editor_document.Document.unexport_port reordered
      ~definition_name:"compound_1" ~side:Output ~name:removable_output))
    "unexport discarded a connected geometry port";
  let removable_level = Editor_document.Document.enter_compound reordered
    root_level reorder_instance |> Option.get in
  let removable_body = Editor_document.Document.network reordered
    removable_level |> Option.get in
  let body_graph = Flow_sop.Network.disconnect
    ~target:Flow_sop.Port.{node = Node.id inner2; path = "in0"}
    removable_body.graph |> Result.get_ok in
  let body_graph = Flow_sop.Network.disconnect
    ~target:Flow_sop.Port.{node = outputs_marker.id;
      path = removable_output} body_graph |> Result.get_ok in
  let removable = Editor_document.Document.with_network reordered
    removable_level {removable_body with graph = body_graph} in
  let removable_parent = Editor_document.Document.network removable
    root_level |> Option.get in
  let parent_graph = Flow_sop.Network.disconnect
    ~target:Flow_sop.Port.{node = reorder_instance;
      path = removable_input} removable_parent.graph |> Result.get_ok in
  let parent_graph = Flow_sop.Network.disconnect
    ~target:Flow_sop.Port.{node = Node.id outer2; path = "in0"}
    parent_graph |> Result.get_ok in
  let fragment = Flow_sop.Network.copy_nodes [reorder_instance]
    parent_graph |> Result.get_ok in
  let parent_graph, copied = Flow_sop.Network.paste fragment parent_graph
    |> Result.get_ok in
  let copied_instance = List.assoc reorder_instance copied in
  let removable = Editor_document.Document.with_network removable
    root_level {removable_parent with graph = parent_graph} in
  let removed_input = Editor_document.Document.unexport_port removable
    ~definition_name:"compound_1" ~side:Input ~name:removable_input
    |> function Ok value -> value
      | Error diagnostic -> failwith (Flow.Diagnostic.to_string diagnostic) in
  let removed_both = Editor_document.Document.unexport_port removed_input
    ~definition_name:"compound_1" ~side:Output ~name:removable_output
    |> Result.get_ok in
  let reduced_parent = Editor_document.Document.network removed_both
    root_level |> Option.get in
  let reduced_definition = Editor_document.Document.String_map.find
    "compound_1" removed_both.definitions in
  let remaining_input = List.find (fun name -> name <> removable_input)
    input_names
  and remaining_output = List.find (fun name -> name <> removable_output)
    output_names in
  check (Edit_graph.node_slot_names reduced_parent.graph.geometry
      ~node_id:reorder_instance = Some [remaining_input]
    && Edit_graph.node_slot_names reduced_parent.graph.geometry
       ~node_id:copied_instance = Some [remaining_input]
    && Edit_graph.node_slot_names reduced_definition.spec.body.geometry
      ~node_id:outputs_marker.id = Some [remaining_output]
    && Flow_sop.Network.geometry_source reduced_parent.graph
      Flow_sop.Port.{node = reorder_instance; path = remaining_input}
       = Flow_sop.Network.geometry_source reordered_parent.graph
         Flow_sop.Port.{node = reorder_instance; path = remaining_input}
    && Flow_sop.Network.geometry_source reduced_parent.graph
      Flow_sop.Port.{node = Node.id outer1; path = "in0"}
       = Flow_sop.Network.geometry_source reordered_parent.graph
         Flow_sop.Port.{node = Node.id outer1; path = "in0"}
    && Result.is_ok (Editor_document.Document.validate removed_both)
    && Result.is_ok (Editor_document.Document.allocate_compiled_ids removed_both))
    "unexporting idle geometry ports changed a remaining named wire";
  let inside = Editor_document.Document.enter_compound grouped root_level grouped_id
    |> Option.get in
  let inside_network = Editor_document.Document.network grouped inside
    |> Option.get in
  let output_id = Edit_graph.inspect inside_network.graph.geometry
    |> List.find (fun (node : Edit_graph.node_info) ->
      node.operation = "flow_outputs") |> fun node -> node.id in
  let idle_body = Flow_sop.Network.disconnect
    ~target:Flow_sop.Port.{node = output_id; path = "result"}
    inside_network.graph |> Result.get_ok in
  let displayed_instance = Editor_document.Document.with_network grouped
    inside {inside_network with graph = idle_body} in
  check (Result.is_error (Editor_document.Document.unexport_port
      displayed_instance ~definition_name:"compound_1" ~side:Output
      ~name:"result"))
    "unexport removed the displayed compound output";
  check (Editor_document.Document.parent_level inside = Some (root_level, grouped_id)
    && Edit_graph.find inside_network.graph.geometry ~node_id:20 <> None
    && Editor_document.Document.resolve_level ~scene_level:false grouped inside
       = Ok inside)
    "compound entry did not resolve the shared definition body";
  let relabelled = Flow_sop.Network.relabel ~node_id:20 "Inside edit"
    inside_network.graph |> Result.get_ok in
  let edited = Editor_document.Document.with_network grouped inside
    {inside_network with graph = relabelled} in
  check (Node.label (Edit_graph.find
      (Editor_document.Document.network edited inside |> Option.get).graph.geometry
      ~node_id:20 |> Option.get) = "Inside edit"
    && Result.is_ok (Editor_document.Document.validate edited))
    "editing inside a compound did not update its shared definition";
  let nested, nested_id = Editor_document.Document.group grouped inside
      ~selected:[20] ~positions:[20, 48., 24.] |> Result.get_ok in
  let nested_level = Editor_document.Document.enter_compound nested inside nested_id
    |> Option.get in
  check (Editor_document.Document.parent_level nested_level = Some (inside, nested_id)
    && Editor_document.Document.resolve_level ~scene_level:false nested nested_level
       = Ok nested_level
    && Result.is_ok (Editor_document.Document.validate nested))
    "nested compound path did not resolve or validate";
  check (Editor_document.Document.resolve_level ~scene_level:false grouped
      nested_level = Ok inside)
    "undoing a nested instance did not return to its surviving parent";
  let nested = Editor_document.Document.allocate_compiled_ids nested
    |> Result.get_ok in
  check (Result.is_ok (Editor_document.Document.validate nested))
    "nested compound IDs failed allocation";
  let ungrouped_nested, nested_mapping =
    Editor_document.Document.ungroup nested inside ~instance_id:nested_id
    |> Result.get_ok in
  check (List.assoc 20 nested_mapping <> 20
    && Editor_document.Document.resolve_level ~scene_level:false
      ungrouped_nested nested_level = Ok inside
    && Result.is_ok (Editor_document.Document.validate ungrouped_nested))
    "ungrouping inside a definition kept a stale nested instance path";
  let grouped = Editor_document.Document.allocate_compiled_ids grouped
    |> Result.get_ok in
  let ungrouped, mapping = Editor_document.Document.ungroup grouped root_level
    ~instance_id:grouped_id |> Result.get_ok in
  let replacement = List.assoc 20 mapping in
  let ungrouped_network = Editor_document.Document.network ungrouped root_level
    |> Option.get in
  check (replacement <> 20
    && Edit_graph.find ungrouped_network.graph.geometry ~node_id:replacement <> None
    && not (Flow_sop.Network.Int_map.mem grouped_id ungrouped_network.graph.instances)
    && ungrouped_network.displayed = Some replacement
    && Flow_sop.Instance_path.Map.is_empty ungrouped.compiled_ids
    && Result.is_ok (Editor_document.Document.validate ungrouped))
    "ungroup did not replace the instance with fresh valid nodes";
  (* Both public hosts: deleting every tile through real UI events empties
     the document and the preview; a document that is not a workspace has no
     preset text to save.  The single-object host keeps its object. *)
  let exercise ~scene_level ~create ~update ~close ~document:current_document
      ~prepared ~graph_nodes =
    let value = ref (create ()) and count = ref 0 in
    Fun.protect ~finally:(fun () -> close !value) (fun () ->
    let step ?keys ?mouse events =
      incr count; value := update !value (frame ?keys ?mouse events !count) in
    let settle predicate =
      let deadline = Unix.gettimeofday () +. 5. in
      while not (predicate !value) && Unix.gettimeofday () < deadline do
        step []; Unix.sleepf 0.001
      done;
      check (predicate !value) "cook did not settle" in
    settle (fun env -> prepared env <> None);
    if scene_level then step [key Input.Space; char 'l'];
    step [];
    let delete label =
      let tile = List.find (fun tile -> tile.Pxui_graph.label = label) (graph_nodes !value) in
      let x, y, w, h = tile.bounds in
      let mouse = float (x + w / 2), float (y + h / 2) in
      step ~mouse [];
      step ~mouse [Event.MousePressed (Input.LeftButton, mouse);
        Event.MouseReleased (Input.LeftButton, mouse)];
      step ~mouse [key Input.Delete]; step [] in
    if scene_level then begin
      (* Remove geometry first; deleting the last camera of an already
         empty scene must not create a replacement. *)
      delete "geo1"; delete "camera1"
    end else List.iter (fun tile -> delete tile.Pxui_graph.label) (graph_nodes !value);
    check (Edit_graph.inspect (current_document !value) = [] && prepared !value = None)
      "delete-all did not clear the document and preview";
    step [key Input.Space; char 's']; step [key Input.Enter]; step [];
    check (Preset.list ~directory = [])
      "a document that is not a workspace saved a preset") in
  let prepares = Atomic.make 0 in
  let prepare _ _ = Atomic.incr prepares; Ok (Atomic.get prepares) in
  let module E3 = Prismel_editor.Editor3 in
  exercise ~scene_level:true
    ~create:(fun () -> E3.create ~graph:code ~presets:directory ~factories ~prepare
      ~scene3:(fun _ _ -> Scene3.create []) () |> Result.get_ok)
    ~update:E3.update ~close:E3.close
    ~document:E3.document ~prepared:E3.prepared ~graph_nodes:E3.graph_nodes;
  let module E2 = Prismel_editor.Editor2 in
  exercise ~scene_level:false
    ~create:(fun () -> E2.create ~graph:code ~presets:directory ~factories ~prepare
      ~scene2:(fun _ _ -> []) () |> Result.get_ok)
    ~update:E2.update ~close:E2.close
    ~document:E2.document ~prepared:E2.prepared ~graph_nodes:E2.graph_nodes;
  (* Value nodes in the editor: append from Time, expression entry, reset. *)
  let program = { Flow_sop.Program.name = "driven"; network = overlay; display = Some 20;
    definitions = Flow_sop.Network.String_map.empty } in
  let editor = ref (E2.create ~program ~presets:directory ~factories ~prepare
    ~scene2:(fun _ _ -> []) () |> Result.get_ok) in
  Fun.protect ~finally:(fun () -> E2.close !editor) (fun () ->
    let count = ref 0 in
    let step ?mouse events =
      incr count; editor := E2.update !editor (frame ?mouse events !count) in
    step []; step [];
    let gx, gy, _, _ = (E2.panes !editor (frame [] 0)).graph in
    let focus = float (gx + 20), float (gy + 150) in
    step ~mouse:focus [Event.MousePressed (Input.LeftButton, focus);
      Event.MouseReleased (Input.LeftButton, focus)];
    step [];
    let clock_tile () = List.find (fun (tile : Pxui_graph.node_view) -> tile.id = clock_id)
        (E2.graph_nodes !editor) in
    let x, y, _, _ = (clock_tile ()).bounds in
    let point = float (x + 50), float (y + 12) in
    step ~mouse:point [Event.MousePressed (Input.LeftButton, point);
      Event.MouseReleased (Input.LeftButton, point)];
    step [char 'h'];
    check (List.exists (fun (tile : Pxui_graph.node_view) ->
      tile.id = clock_id && tile.selected) (E2.graph_nodes !editor))
      "left walk did not select the Time source";
    step [key Input.Tab];
    step [Event.TextInput "Remap"; key Input.Enter]; step [];
    let crash_directory = Filename.temp_dir "prismel-value-append" "" in
    Fun.protect ~finally:(fun () ->
      Array.iter (fun file -> Sys.remove (Filename.concat crash_directory file))
        (Sys.readdir crash_directory);
      Unix.rmdir crash_directory) (fun () ->
      let snapshot () =
        E2.crash_dump !editor crash_directory;
        In_channel.with_open_bin (Filename.concat crash_directory "document.txt") In_channel.input_all in
      let dump = snapshot () in
      let added = List.find_map (fun line ->
        Scanf.sscanf_opt line "  value %d \"Remap\"" Fun.id) (dump_lines dump) in
      check (match added with
        | Some id -> drive_of dump ~node:id ~path:"v" = Some (Printf.sprintf "wire %d.t" clock_id)
        | None -> false)
        "Tab append from Time did not connect the new value node";
      step [char 'h'];
      check (List.exists (fun (tile : Pxui_graph.node_view) ->
        tile.id = clock_id && tile.selected) (E2.graph_nodes !editor))
        "left walk after Tab did not return to Time";
      step [char 'o']; step [];
      let x, y, _, _ = (clock_tile ()).bounds in
      let speed = float (x + 30), float (y + 36) in
      step ~mouse:speed [Event.MouseMoved speed]; step ~mouse:speed [char '='];
      step [key Input.End; Event.TextInput "t*2"; key Input.Enter]; step [];
      let dump = snapshot () in
      check (match drive_of dump ~node:clock_id ~path:"speed" with
        | Some text ->
            String.starts_with ~prefix:"expr " text
            && Flow.Expr.parse_sexp (String.sub text 5 (String.length text - 5))
               |> Result.get_ok |> Flow.Expr.eval ~time:3. = Ok 6.
        | None -> false) "= did not install an expression drive";
      check (value_literal dump ~node:clock_id ~name:"speed" = Some 2.25)
        "expression entry overwrote the stored literal";
      step ~mouse:speed [Event.MouseMoved speed]; step ~mouse:speed [char 'r']; step [];
      let dump = snapshot () in
      check (drive_of dump ~node:clock_id ~path:"speed" = None
        && value_literal dump ~node:clock_id ~name:"speed" = Some 2.25)
        "r on a driven row did not restore its stored literal";
      step ~mouse:speed [Event.MouseMoved speed]; step ~mouse:speed [char 'r']; step [];
      check (value_literal (snapshot ()) ~node:clock_id ~name:"speed" = Some 1.)
        "r on an undriven row did not restore its default";
      step ~mouse:speed [Event.MouseMoved speed]; step ~mouse:speed [char '='];
      step [key Input.End; Event.TextInput "3"; key Input.Enter]; step [];
      let dump = snapshot () in
      check (drive_of dump ~node:clock_id ~path:"speed" = None
        && value_literal dump ~node:clock_id ~name:"speed" = Some 3.)
        "a pure numeric expression did not become a literal";
      step ~mouse:speed [Event.MouseMoved speed]; step ~mouse:speed [char '='];
      step [key Input.End; Event.TextInput "sin("; key Input.Enter]; step [];
      let dump = snapshot () in
      check (drive_of dump ~node:clock_id ~path:"speed" = None
        && value_literal dump ~node:clock_id ~name:"speed" = Some 3.)
        "malformed expression changed the saved document"));
  print_endline "editor document: value overlay, compound operations, both hosts and delete-all passed")
