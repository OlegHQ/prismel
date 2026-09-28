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

let node ?(x = 0.) ?(params = []) id factory inputs = `Assoc [
  "id", `Int id; "factory_key", `String factory; "label", `String factory;
  "inputs", `List inputs; "params", `List params; "x", `Float x; "y", `Float 0.]

let network ?(context = "sop") nodes display = `Assoc [
  "context", `String context; "nodes", `List nodes; "values", `List [];
  "drives", `List []; "display", display]
let extend json fields = match json with `Assoc current -> `Assoc (fields @ current) | _ -> assert false
let set json key value = match json with `Assoc fields ->
  `Assoc (List.map (fun (name, previous) -> name, if name = key then value else previous) fields)
  | _ -> assert false
let owned id value = `Assoc ["object", `Int id; "network", value]
let document ?(camera = `Null) ?(settings = []) ?(view = `Null) scene networks = `Assoc [
  "version", `Int 3; "scene", scene; "networks", `List networks;
  "active_camera", camera; "settings", `List settings; "view", view]

let run () =
  let directory = Filename.temp_dir "prismel-document-contract" "" in
  Fun.protect ~finally:(fun () ->
    Array.iter (fun name -> Sys.remove (Filename.concat directory name)) (Sys.readdir directory);
    Unix.rmdir directory) (fun () ->
  let code = Sop.points [||] in
  let factories = Sop_catalog.Editor.factories in
  let load path = Preset.load ~path ~code ~factories ~settings:Prismel_editor.Settings.none in
  (* Yojson's writer refuses nonfinite floats. Deliberately emit hostile
     numeric tokens to exercise the reader and validation boundary. *)
  let rec hostile_numbers = function
    | `Float x when not (Float.is_finite x) -> `Intlit (if Float.is_nan x then "NaN" else "1e999")
    | `Assoc fields -> `Assoc (List.map (fun (key, json) -> key, hostile_numbers json) fields)
    | `List entries -> `List (List.map hostile_numbers entries)
    | json -> json in
  let write name json =
    let path = Preset.path ~directory ~name in
    Yojson.Safe.to_file ~std:false path (hostile_numbers json); path in
  let empty = network [] `Null in
  let scene_empty = network ~context:"scene" [] `Null in
  let world_empty = network ~context:"world" [] `Null in
  let geometry = node 10 "geometry" [`Null] in
  let scene = network ~context:"scene" [geometry] (`Int 10) in
  let box = node 20 "box" [] in
  let sop = network [box] (`Int 20) in
  let valid = document scene [owned 10 sop] in
  let flow_sop = extend (network [
      extend box ["level", `String "full"; "pinned", `Bool true;
        "rows", `Assoc ["size", `Bool false]; "bypass", `Bool true];
      node 21 "null" [`Int 20]] (`Int 21))
      ["geometry_bends", `List [`Assoc ["to", `List [`Int 21; `String "in0"];
        "bends", `List [`List [`Int 120; `Int 12]]]]] in
  let flow_document = document scene [owned 10 flow_sop] in
  let value id kind label params = `Assoc [
    "id", `Int id; "kind", `String kind; "label", `String label;
    "params", `List params; "x", `Int (-228); "y", `Int 48;
    "level", `String "card"; "pinned", `Bool false;
    "rows", `Assoc []; "split", `List []] in
  let time = value 9 "time" "Clock" [`List [`String "speed"; `Assoc ["float", `Float 2.25]]] in
  let bad_time = value 9 "time" "Clock" [`List [`String "typo"; `Assoc ["float", `Float 1.]]] in
  let math = value 8 "math" "Sine" [`List [`String "op"; `Assoc ["choice", `String "sin"]]] in
  let wire id path from output = `Assoc ["to", `List [`Int id; `String path];
    "wire", `List [`Int from; `String output]; "bends", `List [];
    "wireless", `Bool false] in
  let time_wire = wire 8 "a" 9 "t" |> fun json -> set json "wireless" (`Bool true)
    |> fun json -> set json "bends" (`List [`List [`Int 12; `Int 24]]) in
  let driven_sop = sop
    |> fun json -> set json "nodes" (`List [extend box ["split", `List [`String "center"]]])
    |> fun json -> set json "values" (`List [math; time])
    |> fun json -> set json "drives" (`List [time_wire;
      wire 20 "size" 8 "out";
      `Assoc ["to", `List [`Int 20; `String "center.x"];
        "expr", `String "sin(t * 0.6)"]]) in
  let driven_document = document scene [owned 10 driven_sop] in
  let empty_scene = document scene_empty [] in
  let empty_sop = document scene [owned 10 empty] in
  List.iter (fun (name, json) ->
    let path = write name json in
    let loaded = match load path with Ok loaded -> loaded
      | Error message -> failwith (name ^ ": " ^ message) in
    let saved = Preset.save ~directory ~name:(name ^ "-saved") ~sketch:"contract"
      ~doc:loaded.doc ~view:loaded.view |> Result.get_ok in
    let reloaded = load saved |> Result.get_ok in
    check (List.length (Edit_graph.inspect (Document.scene_graph loaded.doc))
      = List.length (Edit_graph.inspect (Document.scene_graph reloaded.doc)))
      (name ^ " scene changed during round trip");
    let inspect doc = Edit_graph.inspect (Document.scene_graph doc)
      |> List.filter_map (fun (info : Edit_graph.node_info) ->
        Option.map (fun (graph, displayed) ->
          List.length (Edit_graph.inspect graph.Flow_sop.Network.geometry), Option.is_some displayed)
          (Document.object_network doc info.id)) in
    check (inspect loaded.doc = inspect reloaded.doc) (name ^ " network changed during round trip"))
    ["scene-empty", empty_scene; "sop-empty", empty_sop; "valid", valid;
     "flow-layout", flow_document; "driven", driven_document;
     "world-empty", document (network ~context:"scene" [node 30 "world" []] (`Int 30)) [owned 30 world_empty]];
  let flow = load (Preset.path ~directory ~name:"flow-layout-saved") |> Result.get_ok in
  let graph, _ = Option.get (Document.object_network flow.doc 10) in
  check (Edit_graph.find graph.Flow_sop.Network.geometry ~node_id:20 <> None && Edit_graph.find graph.Flow_sop.Network.geometry ~node_id:21 <> None)
    "v3 load did not preserve saved node ids";
  let saved_json = Yojson.Safe.from_file (Preset.path ~directory ~name:"flow-layout-saved") in
  let open Yojson.Safe.Util in
  let saved_network = saved_json |> member "sections" |> member "graph" |> member "networks"
    |> to_list |> List.hd |> member "network" in
  let saved_box = saved_network |> member "nodes" |> to_list |> List.find (fun json ->
    json |> member "id" |> to_int = 20) in
  check (member "level" saved_box = `String "full" && member "pinned" saved_box = `Bool true
    && member "bypass" saved_box = `Bool true
    && member "rows" saved_box = `Assoc ["size", `Bool false]
    && member "geometry_bends" saved_network <> `List [])
    "v3 round trip dropped detail, pins, bypass or bends";
  let driven = load (Preset.path ~directory ~name:"driven-saved") |> Result.get_ok in
  let overlay, _ = Option.get (Document.object_network driven.doc 10) in
  check (List.length (Flow.Graph.inspect overlay.values) = 2
    && Flow_sop.Port.Map.cardinal overlay.drives = 3)
    "v3 round trip dropped value nodes or drives";
  let renamed_value = Flow_sop.Network.relabel ~node_id:9 "Seconds" overlay
    |> Result.get_ok in
  let renamed_box = Flow_sop.Network.relabel ~node_id:20 "Scaled box" renamed_value
    |> Result.get_ok in
  check ((Flow.Graph.find renamed_box.values ~node_id:9 |> Option.get).label = "Seconds"
    && (Edit_graph.find renamed_box.geometry ~node_id:20 |> Option.get
      |> Node.label) = "Scaled box"
    && renamed_box.drives == overlay.drives)
    "Flow rename changed topology or failed to update one node kind";
  check (Flow_sop.Network.relabel ~node_id:9 "" renamed_box
    |> Result.get_ok == renamed_box) "blank rename changed the network";
  let clock = Flow.Graph.find overlay.values ~node_id:9 |> Option.get in
  check (List.exists (fun (field : Param.field_view) ->
    field.name = "speed" && field.current = Param.Float_value 2.25)
    (Flow.Value_kind.fields clock.parameters))
    "v3 round trip changed a value-node literal";
  let expr = match Flow_sop.Port.Map.find_opt
      {Flow_sop.Port.node = 20; path = "center.x"} overlay.drives with
    | Some (Flow_sop.Drive.Expr expr) -> expr
    | _ -> failwith "v3 round trip lost an expression drive" in
  check (abs_float ((Flow.Expr.eval ~time:1. expr |> Result.get_ok) -. sin 0.6) < 1e-12)
    "v3 round trip changed an expression";
  let module Canvas = Editor_core.Network_layout in
  let pane_layout = { Canvas.empty with at = Canvas.Int_map.singleton 9 (-228., 48.);
    bends = Canvas.Port_map.singleton (8, "a") [12., 24.] } in
  let pane = Pxui_graph.create_document overlay |> Pxui_graph.with_layout pane_layout in
  let tile id = List.find (fun (tile : Pxui_graph.node_view) -> tile.id = id)
      (Pxui_graph.node_views pane) in
  check ((tile 9).depth < (tile 8).depth && (tile 8).depth < (tile 20).depth)
    "value wires did not determine left-to-right canvas depth";
  check (Pxui_graph.selected (Pxui_graph.select 9 pane) = Some 9)
    "value tile cannot be selected";
  check (Canvas.Int_map.find_opt 9 (Pxui_graph.layout pane).at = Some (-228., 48.))
    "canvas erased a saved value position";
  let another_box = Sop_catalog.Box.create () in
  let expanded_geometry = Edit_graph.add_node ~factory:(List.find (fun factory ->
    Edit_graph.factory_key factory = "box") factories) another_box overlay.geometry
    |> Result.get_ok in
  let changed = Flow_sop.Network.with_geometry expanded_geometry overlay |> Result.get_ok in
  let pane = Pxui_graph.with_document changed pane in
  check (Canvas.Port_map.mem (8, "a") (Pxui_graph.layout pane).bends)
    "geometry edit erased a value wire bend";
  let driven_saved = Yojson.Safe.from_file (Preset.path ~directory ~name:"driven-saved")
    |> member "sections" |> member "graph" |> member "networks" |> to_list
    |> List.hd |> member "network" in
  check (List.length (driven_saved |> member "values" |> to_list) = 2
    && List.length (driven_saved |> member "drives" |> to_list) = 3
    && (driven_saved |> member "drives" |> to_list |> List.hd |> member "wireless") = `Bool true)
    "v3 writer omitted value nodes or drives";
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
  let successful = Preset.path ~directory ~name:"valid-saved" in
  let before = In_channel.with_open_bin successful In_channel.input_all in
  let loaded = load successful |> Result.get_ok in
  check (Result.is_error (Preset.save ~directory ~name:"valid-saved" ~sketch:"contract"
    ~doc:loaded.doc ~view:(`Assoc ["zoom", `Float infinity])))
    "save accepted a nonfinite viewport";
  check (In_channel.with_open_bin successful In_channel.input_all = before)
    "rejected save replaced the last successful preset";
  let compound_body = network [
    node 71 "flow.inputs:compound_1" [];
    node 70 "box" [];
    node 72 "flow.outputs:compound_1" []] (`Int 70) in
  let interface = `Assoc ["name", `String "amp"; "type", `String "Float";
    "default", `Assoc ["float", `Float 1.]; "label", `String "Amplitude";
    "soft", `List [`Float 0.; `Float 2.]] in
  let definition = `Assoc ["name", `String "compound_1";
    "context", `String "sop"; "inputs", `List [interface];
    "outputs", `List []; "body", compound_body] in
  let with_definition = extend valid ["definitions", `List [definition]] in
  let loaded_definition = load (write "definition" with_definition) |> Result.get_ok in
  let saved_definition = Preset.save ~directory ~name:"definition-saved"
    ~sketch:"contract" ~doc:loaded_definition.doc ~view:`Null |> Result.get_ok in
  let definition_json = Yojson.Safe.from_file saved_definition
    |> member "sections" |> member "graph" |> member "definitions" |> to_list in
  check (List.length definition_json = 1
      && (List.hd definition_json |> member "name") = `String "compound_1"
      && (List.hd definition_json |> member "inputs" |> to_list |> List.hd
          |> member "default") = `Assoc ["float", `Float 1.])
    "compound definition interface or body did not round trip";
  ignore (load saved_definition |> Result.get_ok);
  let instance id definition = `Assoc ["id", `Int id;
    "definition", `String definition; "literals", `List []] in
  let geometry_output = `Assoc ["name", `String "result";
    "type", `String "Geometry"; "default", `Null;
    "label", `String "Result"; "soft", `Null] in
  let instance_body = network [
    node 71 "flow.inputs:compound_1" [];
    node 70 "box" [];
    node 72 "flow.outputs:compound_1" [`Int 70]] (`Int 72) in
  let instance_definition = set definition "outputs" (`List [geometry_output])
    |> fun json -> set json "body" instance_body in
  let instance_network = network [
      node 20 "flow.instance:compound_1" [];
      node 21 "null" [`Int 20]] (`Int 21)
    |> fun json -> extend json ["instances", `List [instance 20 "compound_1"];
      "geometry_outputs", `List [`Assoc ["to", `List [`Int 21; `String "in0"];
        "output", `String "result"]]] in
  let with_instance = set with_definition "definitions" (`List [instance_definition])
    |> fun json -> set json "networks" (`List [owned 10 instance_network])
    |> fun json -> extend json ["compiled_ids", `List [
      `Assoc ["path", `List [`Int 20; `Int 70]; "id", `Int 90]]] in
  let loaded_instance = load (write "instance-ids" with_instance) |> Result.get_ok in
  let saved_instance = Preset.save ~directory ~name:"instance-ids-saved"
    ~sketch:"contract" ~doc:loaded_instance.doc ~view:`Null |> Result.get_ok in
  let saved_ids = Yojson.Safe.from_file saved_instance |> member "sections"
    |> member "graph" |> member "compiled_ids" in
  check (saved_ids = `List [`Assoc ["path", `List [`Int 20; `Int 70];
      "id", `Int 90]])
    "compiled instance ids did not round trip";
  let saved_network = Yojson.Safe.from_file saved_instance |> member "sections"
    |> member "graph" |> member "networks" |> to_list |> List.hd
    |> member "network" in
  check (saved_network |> member "geometry_outputs" |> to_list
    |> List.hd |> member "output" = `String "result")
    "named compound geometry output did not round trip";
  ignore (load saved_instance |> Result.get_ok);
  let unallocated = set with_instance "compiled_ids" (`List []) in
  let direct = Editor_document.Preset.load
    ~path:(write "instance-unallocated" unallocated) ~code ~factories
    ~settings:Editor_document.Settings.none |> Result.get_ok in
  let allocated = match Editor_document.Document.allocate_compiled_ids direct.doc with
    | Ok doc -> doc
    | Error diagnostic -> failwith (Flow.Diagnostic.to_string diagnostic) in
  let saved_id = Flow_sop.Instance_path.Map.find [20; 70]
    allocated.compiled_ids in
  check (saved_id > 0 && Result.is_ok (Editor_document.Document.validate allocated))
    "compound compiled id was not allocated into a valid document";
  let allocated_path = Editor_document.Preset.save ~directory
    ~name:"instance-allocated-saved" ~sketch:"contract" ~doc:allocated
    ~view:`Null |> Result.get_ok in
  let reloaded_allocated = Editor_document.Preset.load ~path:allocated_path
    ~code ~factories ~settings:Editor_document.Settings.none |> Result.get_ok in
  check (Flow_sop.Instance_path.Map.find [20; 70]
      reloaded_allocated.doc.compiled_ids = saved_id)
    "compound compiled id changed across save and reload";
  let direct = Editor_document.Preset.load ~path:(write "group-source" valid)
    ~code ~factories ~settings:Editor_document.Settings.none |> Result.get_ok in
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
  let exported_path = Editor_document.Preset.save ~directory
    ~name:"exported-interface-saved" ~sketch:"contract" ~doc:exported
    ~view:`Null |> Result.get_ok in
  let reloaded_export = Editor_document.Preset.load ~path:exported_path
    ~code ~factories ~settings:Editor_document.Settings.none |> Result.get_ok in
  check (Result.is_ok (Editor_document.Document.validate reloaded_export.doc))
    "exported value interface failed preset round trip";
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
  let unique_path = Editor_document.Preset.save ~directory
    ~name:"unique-saved" ~sketch:"contract" ~doc:unique ~view:`Null
    |> Result.get_ok in
  let reloaded_unique = Editor_document.Preset.load ~path:unique_path
    ~code ~factories ~settings:Editor_document.Settings.none
    |> Result.get_ok in
  check (Result.is_ok (Editor_document.Document.validate reloaded_unique.doc)
    && Editor_document.Document.String_map.cardinal
      reloaded_unique.doc.definitions = 2)
    "make unique did not survive preset round trip";
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
  let renamed_path = Editor_document.Preset.save ~directory
    ~name:"renamed-interface-saved" ~sketch:"contract" ~doc:wired ~view:`Null
    |> Result.get_ok in
  let reloaded_renamed = Editor_document.Preset.load ~path:renamed_path
    ~code ~factories ~settings:Editor_document.Settings.none
    |> function Ok value -> value | Error message -> failwith message in
  check (Result.is_ok (Editor_document.Document.validate reloaded_renamed.doc))
    "renamed compound interface failed preset round trip";
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
  let inside = Editor_document.Document.enter_compound grouped root_level grouped_id
    |> Option.get in
  let inside_network = Editor_document.Document.network grouped inside
    |> Option.get in
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
  let nested_path = Editor_document.Preset.save ~directory
    ~name:"nested-group-saved" ~sketch:"contract" ~doc:nested ~view:`Null
    |> Result.get_ok in
  let reloaded_nested = Editor_document.Preset.load ~path:nested_path
    ~code ~factories ~settings:Editor_document.Settings.none
    |> Result.get_ok in
  check (Editor_document.Document.resolve_level ~scene_level:false
      reloaded_nested.doc nested_level = Ok nested_level
    && reloaded_nested.doc.compiled_ids = nested.compiled_ids)
    "nested compound path or compiled IDs changed on preset reload";
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
  let grouped_path = Editor_document.Preset.save ~directory
    ~name:"grouped-saved" ~sketch:"contract" ~doc:grouped ~view:`Null
    |> Result.get_ok in
  ignore (Editor_document.Preset.load ~path:grouped_path ~code ~factories
    ~settings:Editor_document.Settings.none |> Result.get_ok);
  let geometry_input = `Assoc ["name", `String "incoming";
    "type", `String "Geometry"; "default", `Null;
    "label", `String "Incoming"; "soft", `Null] in
  let marker_body = network [
      node 71 "flow.inputs:compound_2" [];
      node 72 "flow.outputs:compound_2" [`Int 71]] (`Int 72)
    |> fun json -> extend json ["geometry_outputs", `List [
      `Assoc ["to", `List [`Int 72; `String "result"];
        "output", `String "incoming"]]] in
  let marker_definition = `Assoc ["name", `String "compound_2";
    "context", `String "sop"; "inputs", `List [geometry_input];
    "outputs", `List [geometry_output]; "body", marker_body] in
  let marker_network = network [
      node 22 "box" [];
      node 20 "flow.instance:compound_2" [`Int 22];
      node 21 "null" [`Int 20]] (`Int 21)
    |> fun json -> extend json ["instances", `List [instance 20 "compound_2"];
      "geometry_outputs", `List [
        `Assoc ["to", `List [`Int 21; `String "in0"];
          "output", `String "result"]]] in
  let marker_preset = document scene [owned 10 marker_network]
    |> fun json -> extend json ["definitions", `List [marker_definition]] in
  let loaded_marker = load (write "compound-markers" marker_preset)
    |> Result.get_ok in
  let marker_graph, _ = Option.get (Document.object_network loaded_marker.doc 10) in
  check (Edit_graph.node_slot_names marker_graph.geometry ~node_id:20
      = Some ["incoming"])
    "compound instance geometry slot was not restored";
  let saved_marker = Preset.save ~directory ~name:"compound-markers-saved"
    ~sketch:"contract" ~doc:loaded_marker.doc ~view:`Null |> Result.get_ok in
  let reloaded_marker = load saved_marker |> Result.get_ok in
  let marker_graph, _ = Option.get (Document.object_network reloaded_marker.doc 10) in
  check (Edit_graph.node_slot_names marker_graph.geometry ~node_id:20
      = Some ["incoming"])
    "compound instance lost its input slot on preset round trip";
  let saved_body = Yojson.Safe.from_file saved_marker |> member "sections"
    |> member "graph" |> member "definitions" |> to_list |> List.hd
    |> member "body" in
  check (saved_body |> member "nodes" |> to_list |> List.exists (fun json ->
      member "factory_key" json = `String "flow.inputs:compound_2")
    && saved_body |> member "nodes" |> to_list |> List.exists (fun json ->
      member "factory_key" json = `String "flow.outputs:compound_2")
    && saved_body |> member "geometry_outputs" |> to_list |> List.hd
      |> member "output" = `String "incoming")
    "compound definition lost its interface markers or routed input";
  let bad_instance_network = set instance_network "geometry_outputs" (`List [
    `Assoc ["to", `List [`Int 21; `String "in0"];
      "output", `String "absent"]]) in
  let wrong_owner = node 11 "camera" [] in
  let malformed = [
    "missing-interface-markers", set with_definition "definitions"
      (`List [set definition "body" (network [node 70 "box" []] (`Int 70))]);
    "orphan-compound-node", set marker_preset "networks"
      (`List [owned 10 (set marker_network "instances" (`List []))]);
    "root-interface-marker", set marker_preset "networks"
      (`List [owned 10 (network
        [node 20 "flow.inputs:compound_2" []] (`Int 20))]);
    "wrong-instance-role", set with_instance "networks"
      (`List [owned 10 (set instance_network "nodes"
        (`List [box; node 21 "null" [`Int 20]]))]);
    "recursive-definition", extend valid ["definitions", `List [set definition "body"
      (extend compound_body ["instances", `List [instance 70 "compound_1"]])]];
    "missing-definition", document scene [owned 10
      (extend sop ["instances", `List [instance 20 "missing"]])];
    "duplicate-compiled-id", extend valid ["compiled_ids", `List [
      `Assoc ["path", `List [`Int 20; `Int 70]; "id", `Int 99];
      `Assoc ["path", `List [`Int 20; `Int 71]; "id", `Int 99]]];
    "invalid-compiled-path", extend valid ["compiled_ids", `List [
      `Assoc ["path", `List [`Int (-1); `Int 70]; "id", `Int 99]]];
    "orphan-compiled-path", extend with_definition ["compiled_ids", `List [
      `Assoc ["path", `List [`Int 20; `Int 70]; "id", `Int 99]]];
    "unknown-geometry-output", set with_instance "networks"
      (`List [owned 10 bad_instance_network]);
    "old-version-1", `Assoc ["version", `Int 1; "scene", scene; "networks", `List [owned 10 sop]];
    "old-version-2", `Assoc ["version", `Int 2; "scene", scene; "networks", `List [owned 10 sop]];
    "missing-values", document scene [owned 10 (`Assoc ["context", `String "sop";
      "nodes", `List [box]; "drives", `List []; "display", `Int 20])];
    "missing-drives", document scene [owned 10 (`Assoc ["context", `String "sop";
      "nodes", `List [box]; "values", `List []; "display", `Int 20])];
    "wrong-context", document scene [owned 10 (set sop "context" (`String "world"))];
    "value-in-scene", document (set scene "values" (`List [time])) [owned 10 sop];
    "value-id-collision", document scene [owned 10 (set driven_sop "values" (`List [
      value 20 "time" "Collision" []]))];
    "invalid-wire", document scene [owned 10 (set driven_sop "drives" (`List [wire 20 "size" 99 "out"]))];
    "duplicate-drive", document scene [owned 10 (set driven_sop "drives" (`List [time_wire; time_wire]))];
    "wire-type", document scene [owned 10 (set driven_sop "drives" (`List [wire 20 "normals" 9 "t"]))];
    "wire-cycle", document scene [owned 10 (set driven_sop "drives" (`List [
      wire 8 "a" 9 "t"; wire 9 "speed" 8 "out"]))];
    "split-whole-vector", document scene [owned 10 (set
      (set driven_sop "nodes" (`List [extend box ["split", `List [`String "size"]]]))
      "drives" (`List [wire 20 "size" 8 "out"]))];
    "bad-expression", document scene [owned 10 (set driven_sop "drives" (`List [
      `Assoc ["to", `List [`Int 20; `String "center.x"]; "expr", `String "sin("]]))];
    "expression-bends", document scene [owned 10 (set driven_sop "drives" (`List [
      `Assoc ["to", `List [`Int 20; `String "center.x"]; "expr", `String "t";
        "bends", `List []]]))];
    "unknown-geometry-parameter", document scene [owned 10 (network [node ~params:[
      `List [`String "typo"; `Assoc ["float", `Float 1.]]] 20 "box" []] (`Int 20))];
    "unknown-value-parameter", document scene [owned 10 (set driven_sop "values" (`List [bad_time]))];
    "unsplit-component", document scene [owned 10 (set driven_sop "nodes" (`List [box]))];
    "bad-level", document scene [owned 10 (network [extend box ["level", `String "detail"]] (`Int 20))];
    "bad-pin", document scene [owned 10 (network [extend box ["pinned", `Int 1]] (`Int 20))];
    "bad-bypass", document scene [owned 10 (network [extend box ["bypass", `Int 1]] (`Int 20))];
    "missing-row", document scene [owned 10 (network [extend box ["rows", `Assoc ["absent", `Bool true]]] (`Int 20))];
    "missing-bend-port", document scene [owned 10 (extend sop ["geometry_bends", `List [
      `Assoc ["to", `List [`Int 20; `String "in0"]; "bends", `List []]]])];
    "nonfinite-bend", document scene [owned 10 (extend (network [box; node 21 "null" [`Int 20]] (`Int 21))
      ["geometry_bends", `List [`Assoc ["to", `List [`Int 21; `String "in0"];
        "bends", `List [`List [`Float infinity; `Int 12]]]]])];
    "missing-network", document scene [];
    "missing-owner", document scene [owned 99 sop];
    "duplicate-owner", document scene [owned 10 sop; owned 10 sop];
    "wrong-owner", document (network ~context:"scene" [geometry; wrong_owner] (`Int 10))
      [owned 10 sop; owned 11 sop];
    "duplicate-scene-id", document (network ~context:"scene" [geometry; geometry] (`Int 10)) [owned 10 sop];
    "duplicate-sop-id", document scene [owned 10 (network [box; box] (`Int 20))];
    "dangling-display", document scene [owned 10 (network [box] (`Int 99))];
    "empty-dangling-display", document scene [owned 10 (network [] (`Int 20))];
    "dangling-camera", document ~camera:(`Int 99) scene [owned 10 sop];
    "wrong-camera-kind", document ~camera:(`Int 10) scene [owned 10 sop];
    "dangling-input", document scene [owned 10
      (network [node 20 "null" [`Int 99]] (`Int 20))];
    "wrong-arity", document scene [owned 10 (network [node 20 "box" [`Null]] (`Int 20))];
    "cycle", document scene [owned 10 (network
      [node 20 "null" [`Int 21]; node 21 "null" [`Int 20]] (`Int 20))];
    "infinite-position", document scene [owned 10 (network [node ~x:infinity 20 "box" []] (`Int 20))];
    "nan-parameter", document scene [owned 10 (network [node ~params:[
      `List [`String "size_x"; `Assoc ["float", `Float nan]]] 20 "box" []] (`Int 20))];
    "infinite-settings", document ~settings:[
      `List [`String "any"; `Assoc ["float", `Float infinity]]] scene [owned 10 sop];
    "infinite-viewport", document ~view:(`Assoc ["zoom", `Float infinity]) scene [owned 10 sop];
    "bad-display-type", document (network ~context:"scene" [geometry] (`String "10")) [owned 10 sop];
    "bad-factory-type", document (network ~context:"scene" [`Assoc ["id", `Int 10;
      "factory_key", `Int 1; "inputs", `List []]] (`Int 10)) [];
    "duplicate-json-field", `Assoc ["version", `Int 3; "version", `Int 1];
  ] in
  List.iter (fun (name, json) ->
    match load (write name json) with
    | Error message -> check (message <> "") (name ^ " has no explanation")
    | Ok _ -> failwith ("accepted malformed document: " ^ name)) malformed;

  (* Both public hosts install valid loads as undo steps, reject malformed
     loads without touching document/camera/history/preview, and clear empty
     SOP previews. The single-object host rejects an empty scene safely. *)
  let exercise ~scene_level ~create ~update ~close ~crash_dump ~document:current_document
      ~scene_document ~prepared ~camera ~can_undo ~can_redo ~graph_nodes =
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
    let browse name =
      step [key Input.Space; char 'b'];
      step [Event.TextInput name; key Input.Enter]; step [] in
    let undo () = step ~keys:[Input.Meta] [char 'z']; step [] in
    let redo () = step ~keys:[Input.Meta; Input.Shift] [char 'z']; step [] in
    settle (fun env -> prepared env <> None);
    let original = current_document !value and original_scene = scene_document !value
    and original_camera = camera !value and preview = prepared !value in
    let history = can_undo !value, can_redo !value in
    browse "missing-network";
    check (current_document !value == original && scene_document !value == original_scene
      && camera !value == original_camera && prepared !value = preview
      && (can_undo !value, can_redo !value) = history)
      "rejected load changed installed state";
    browse "sop-empty-saved";
    check (Edit_graph.inspect (current_document !value) = [] || scene_level)
      "empty SOP was not installed";
    check (prepared !value = None && can_undo !value) "empty SOP retained stale preview";
    undo ();
    check (scene_document !value == original_scene) "load undo did not restore the original document";
    settle (fun env -> prepared env <> None);
    redo ();
    check (prepared !value = None) "load redo retained stale preview";
    let before_scene = scene_document !value and before_doc = current_document !value
    and before_camera = camera !value in
    browse "scene-empty-saved";
    if scene_level then begin
      check (Edit_graph.inspect (scene_document !value) = [] && prepared !value = None)
        "empty scene was repopulated or retained a preview";
      undo (); check (scene_document !value == before_scene) "empty scene load undo failed";
      redo (); check (Edit_graph.inspect (scene_document !value) = []) "empty scene load redo failed"
    end else
      check (scene_document !value == before_scene && current_document !value == before_doc
        && camera !value == before_camera && prepared !value = None)
        "Editor2 installed an incompatible empty scene";
    (* Delete every editable tile through real UI events, save with the
       standard prompt, and reload that exact generated preset. *)
    undo (); if scene_level then undo ();
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
    let crash_directory = Filename.temp_dir "prismel-empty-crash" "" in
    Fun.protect ~finally:(fun () ->
      Array.iter (fun name -> Sys.remove (Filename.concat crash_directory name))
        (Sys.readdir crash_directory);
      Unix.rmdir crash_directory) (fun () ->
      crash_dump !value crash_directory;
      let dumped = load (Filename.concat crash_directory "document.json") |> Result.get_ok in
      let scene = Document.scene_graph dumped.doc in
      if scene_level then check (Edit_graph.inspect scene = []) "crash preset repopulated an empty scene"
      else
        let id = (List.find (fun (info : Edit_graph.node_info) -> info.operation = "geometry")
          (Edit_graph.inspect scene)).id in
        match Document.object_network dumped.doc id with
        | Some (graph, None) when Edit_graph.inspect graph.Flow_sop.Network.geometry = [] -> ()
        | _ -> failwith "crash preset did not preserve an empty SOP");
    step [key Input.Space; char 's']; step [key Input.Enter]; step [];
    let generated = Preset.list ~directory |> List.find_map (fun (name, _) ->
      if String.length name > 0 && name.[0] >= '0' && name.[0] <= '9'
      then Some name else None) |> Option.get in
    check (Result.is_ok (load (Preset.path ~directory ~name:generated)))
      "delete-all save was not reloadable by the real loader";
    browse generated;
    check (Edit_graph.inspect (current_document !value) = [] && prepared !value = None)
      "delete-all reload changed intentional emptiness") in
  let prepares = Atomic.make 0 in
  let prepare _ _ = Atomic.incr prepares; Ok (Atomic.get prepares) in
  let module E3 = Prismel_editor.Editor3 in
  exercise ~scene_level:true
    ~create:(fun () -> E3.create ~graph:code ~presets:directory ~factories ~prepare
      ~scene3:(fun _ _ -> Scene3.create []) () |> Result.get_ok)
    ~update:E3.update ~close:E3.close ~crash_dump:E3.crash_dump
    ~document:E3.document ~scene_document:E3.scene_document
    ~prepared:E3.prepared ~camera:E3.camera ~can_undo:E3.can_undo ~can_redo:E3.can_redo
    ~graph_nodes:E3.graph_nodes;
  (* The second host must save its own empty state rather than reuse E3's
     same-second generated filename. *)
  Preset.list ~directory |> List.iter (fun (name, _) ->
    if name.[0] >= '0' && name.[0] <= '9' then
      Preset.delete ~directory ~name |> Result.get_ok);
  let module E2 = Prismel_editor.Editor2 in
  exercise ~scene_level:false
    ~create:(fun () -> E2.create ~graph:code ~presets:directory ~factories ~prepare
      ~scene2:(fun _ _ -> []) () |> Result.get_ok)
    ~update:E2.update ~close:E2.close ~crash_dump:E2.crash_dump
    ~document:E2.document ~scene_document:E2.document
    ~prepared:E2.prepared ~camera:E2.camera ~can_undo:E2.can_undo ~can_redo:E2.can_redo
    ~graph_nodes:E2.graph_nodes;
  let editor = ref (E2.create ~graph:code ~presets:directory ~factories ~prepare
    ~scene2:(fun _ _ -> []) () |> Result.get_ok) in
  Fun.protect ~finally:(fun () -> E2.close !editor) (fun () ->
    let count = ref 0 in
    let step ?mouse events =
      incr count; editor := E2.update !editor (frame ?mouse events !count) in
    step [key Input.Space; char 'b'];
    step [Event.TextInput "driven-saved"; key Input.Enter]; step [];
    let gx, gy, _, _ = (E2.panes !editor (frame [] 0)).graph in
    let focus = float (gx + 20), float (gy + 150) in
    step ~mouse:focus [Event.MousePressed (Input.LeftButton, focus);
      Event.MouseReleased (Input.LeftButton, focus)];
    step [key Input.Home]; step [];
    let clock = List.find (fun (tile : Pxui_graph.node_view) -> tile.id = 9)
        (E2.graph_nodes !editor) in
    let x, y, _, _ = clock.bounds in
    let point = float (x + 50), float (y + 12) in
    step ~mouse:point [Event.MousePressed (Input.LeftButton, point);
      Event.MouseReleased (Input.LeftButton, point)];
    step [char 'h'];
    check (List.exists (fun (tile : Pxui_graph.node_view) ->
      tile.id = 9 && tile.selected) (E2.graph_nodes !editor))
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
        let saved = load (Filename.concat crash_directory "document.json")
          |> Result.get_ok in
        fst (Option.get (Document.object_network saved.doc 10)) in
      let overlay = snapshot () in
      let added = Flow.Graph.inspect overlay.values |> List.find (fun (node : Flow.Graph.node) ->
        node.label = "Remap") in
      check (Flow_sop.Port.Map.find_opt
        {Flow_sop.Port.node = added.id; path = "v"} overlay.drives =
        Some (Flow_sop.Drive.Wire {node = 9; output = "t"}))
        "Tab append from Time did not connect the new value node";
      let clock = List.find (fun (tile : Pxui_graph.node_view) -> tile.id = 9)
          (E2.graph_nodes !editor) in
      ignore clock;
      step [char 'h'];
      check (List.exists (fun (tile : Pxui_graph.node_view) ->
        tile.id = 9 && tile.selected) (E2.graph_nodes !editor))
        "left walk after Tab did not return to Time";
      step [char 'o']; step [];
      let clock = List.find (fun (tile : Pxui_graph.node_view) -> tile.id = 9)
          (E2.graph_nodes !editor) in
      let x, y, _, _ = clock.bounds in
      let speed = float (x + 30), float (y + 20) in
      step ~mouse:speed [Event.MouseMoved speed]; step ~mouse:speed [char '='];
      step [key Input.End; Event.TextInput "t*2"; key Input.Enter]; step [];
      let overlay = snapshot () in
      let speed_port = {Flow_sop.Port.node = 9; path = "speed"} in
      check (match Flow_sop.Port.Map.find_opt speed_port overlay.drives with
        | Some (Flow_sop.Drive.Expr expression) ->
            Flow.Expr.eval ~time:3. expression = Ok 6.
        | _ -> false) "= did not install an expression drive";
      let speed_literal (overlay : Flow_sop.Network.t) =
        let node = Flow.Graph.find overlay.values ~node_id:9 |> Option.get in
        let field = List.find (fun (field : Param.field_view) ->
          field.name = "speed") (Flow.Value_kind.fields node.parameters) in
        field.current in
      check (speed_literal overlay = Param.Float_value 2.25)
        "expression entry overwrote the stored literal";
      step ~mouse:speed [Event.MouseMoved speed]; step ~mouse:speed [char 'r']; step [];
      let overlay = snapshot () in
      check (Flow_sop.Port.Map.find_opt speed_port overlay.drives = None
        && speed_literal overlay = Param.Float_value 2.25)
        "r on a driven row did not restore its stored literal";
      step ~mouse:speed [Event.MouseMoved speed]; step ~mouse:speed [char 'r']; step [];
      let overlay = snapshot () in
      check (speed_literal overlay = Param.Float_value 1.)
        "r on an undriven row did not restore its default";
      step ~mouse:speed [Event.MouseMoved speed]; step ~mouse:speed [char '='];
      step [key Input.End; Event.TextInput "3"; key Input.Enter]; step [];
      let overlay = snapshot () in
      check (Flow_sop.Port.Map.find_opt speed_port overlay.drives = None
        && speed_literal overlay = Param.Float_value 3.)
        "a pure numeric expression did not become a literal";
      step ~mouse:speed [Event.MouseMoved speed]; step ~mouse:speed [char '='];
      step [key Input.End; Event.TextInput "sin("; key Input.Enter]; step [];
      let overlay = snapshot () in
      check (Flow_sop.Port.Map.find_opt speed_port overlay.drives = None
        && speed_literal overlay = Param.Float_value 3.)
        "malformed expression changed the saved document"));
  print_endline "editor document: empty round trips, validation, both hosts, load history and delete-all passed")
