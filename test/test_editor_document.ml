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

let network nodes display = `Assoc ["nodes", `List nodes; "display", display]
let extend json fields = match json with `Assoc current -> `Assoc (fields @ current) | _ -> assert false
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
  let geometry = node 10 "geometry" [`Null] in
  let scene = network [geometry] (`Int 10) in
  let box = node 20 "box" [] in
  let sop = network [box] (`Int 20) in
  let valid = document scene [owned 10 sop] in
  let flow_sop = extend (network [
      extend box ["level", `String "full"; "pinned", `Bool true;
        "rows", `Assoc ["size_x", `Bool false]];
      node 21 "null" [`Int 20]] (`Int 21))
      ["geometry_bends", `List [`Assoc ["to", `List [`Int 21; `String "in0"];
        "bends", `List [`List [`Int 120; `Int 12]]]]] in
  let flow_document = document scene [owned 10 flow_sop] in
  let empty_scene = document empty [] in
  let empty_sop = document scene [owned 10 empty] in
  List.iter (fun (name, json) ->
    let path = write name json in
    let loaded = load path |> Result.get_ok in
    let saved = Preset.save ~directory ~name:(name ^ "-saved") ~sketch:"contract"
      ~doc:loaded.doc ~view:loaded.view |> Result.get_ok in
    let reloaded = load saved |> Result.get_ok in
    check (List.length (Edit_graph.inspect (Document.scene_graph loaded.doc))
      = List.length (Edit_graph.inspect (Document.scene_graph reloaded.doc)))
      (name ^ " scene changed during round trip");
    let inspect doc = Edit_graph.inspect (Document.scene_graph doc)
      |> List.filter_map (fun (info : Edit_graph.node_info) ->
        Option.map (fun (graph, displayed) ->
          List.length (Edit_graph.inspect graph), Option.is_some displayed)
          (Document.object_network doc info.id)) in
    check (inspect loaded.doc = inspect reloaded.doc) (name ^ " network changed during round trip"))
    ["scene-empty", empty_scene; "sop-empty", empty_sop; "valid", valid;
     "flow-layout", flow_document;
     "world-empty", document (network [node 30 "world" []] (`Int 30)) [owned 30 empty]];
  let flow = load (Preset.path ~directory ~name:"flow-layout-saved") |> Result.get_ok in
  let graph, _ = Option.get (Document.object_network flow.doc 10) in
  check (Edit_graph.find graph ~node_id:20 <> None && Edit_graph.find graph ~node_id:21 <> None)
    "v3 load did not preserve saved node ids";
  let saved_json = Yojson.Safe.from_file (Preset.path ~directory ~name:"flow-layout-saved") in
  let open Yojson.Safe.Util in
  let saved_network = saved_json |> member "sections" |> member "graph" |> member "networks"
    |> to_list |> List.hd |> member "network" in
  let saved_box = saved_network |> member "nodes" |> to_list |> List.find (fun json ->
    json |> member "id" |> to_int = 20) in
  check (member "level" saved_box = `String "full" && member "pinned" saved_box = `Bool true
    && member "rows" saved_box = `Assoc ["size_x", `Bool false]
    && member "geometry_bends" saved_network <> `List [])
    "v3 round trip dropped detail, pins or bends";
  let successful = Preset.path ~directory ~name:"valid-saved" in
  let before = In_channel.with_open_bin successful In_channel.input_all in
  let loaded = load successful |> Result.get_ok in
  check (Result.is_error (Preset.save ~directory ~name:"valid-saved" ~sketch:"contract"
    ~doc:loaded.doc ~view:(`Assoc ["zoom", `Float infinity])))
    "save accepted a nonfinite viewport";
  check (In_channel.with_open_bin successful In_channel.input_all = before)
    "rejected save replaced the last successful preset";
  let wrong_owner = node 11 "camera" [] in
  let malformed = [
    "old-version-1", `Assoc ["version", `Int 1; "scene", scene; "networks", `List [owned 10 sop]];
    "old-version-2", `Assoc ["version", `Int 2; "scene", scene; "networks", `List [owned 10 sop]];
    "bad-level", document scene [owned 10 (network [extend box ["level", `String "detail"]] (`Int 20))];
    "bad-pin", document scene [owned 10 (network [extend box ["pinned", `Int 1]] (`Int 20))];
    "missing-row", document scene [owned 10 (network [extend box ["rows", `Assoc ["absent", `Bool true]]] (`Int 20))];
    "missing-bend-port", document scene [owned 10 (extend sop ["geometry_bends", `List [
      `Assoc ["to", `List [`Int 20; `String "in0"]; "bends", `List []]]])];
    "nonfinite-bend", document scene [owned 10 (extend (network [box; node 21 "null" [`Int 20]] (`Int 21))
      ["geometry_bends", `List [`Assoc ["to", `List [`Int 21; `String "in0"];
        "bends", `List [`List [`Float infinity; `Int 12]]]]])];
    "missing-network", document scene [];
    "missing-owner", document scene [owned 99 sop];
    "duplicate-owner", document scene [owned 10 sop; owned 10 sop];
    "wrong-owner", document (network [geometry; wrong_owner] (`Int 10))
      [owned 10 sop; owned 11 sop];
    "duplicate-scene-id", document (network [geometry; geometry] (`Int 10)) [owned 10 sop];
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
    "bad-display-type", document (network [geometry] (`String "10")) [owned 10 sop];
    "bad-factory-type", document (network [`Assoc ["id", `Int 10;
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
        | Some (graph, None) when Edit_graph.inspect graph = [] -> ()
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
  print_endline "editor document: empty round trips, validation, both hosts, load history and delete-all passed")
