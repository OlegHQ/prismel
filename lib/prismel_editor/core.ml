open Prismel
open Procedural
open Common

type bounds = Cook.bounds

(* How the graph pane shows the open network. *)
type projection = Graph_view | List_view

type prompt =
  | Saving of string
  | Palette of string  (* command search query *)
  | Browsing of { query : string; presets : (string * float) list }

type prompt_intent = Save_preset_file of string | Load_preset_file of string
  | Delete_preset_file of { name : string; query : string }
  | Run_action of Leader.action

type timeline_intent = Pxui_shell.Timeline_bar.intent =
  Pause_toggle | Stop_playback | Reset_playback | Seek_playback of int64

type 'panel frame_result = {
  workspace : Workspace.t;
  focus : Workspace.column;
  pane_keys : (int * Workspace.column) list;
  graph_view : Pxui_graph.t;
  tree : Pxui_shell.Tree.t;
  document : Edit_graph.t;  (* the open network after this frame's edits *)
  edit_error : string option;
  effects : Parameter.effects;
  timeline_intents : timeline_intent list;
  frame_request : int option;
  prompt : prompt option;
  prompt_intent : prompt_intent option;
  panel : 'panel option;
  grab : bool;  (* a viewport handle holds the pointer *)
  settings : Settings.t;
  touched : bool;  (* a graph intent changed layout, display, or flag *)
  placed : int list;  (* tiles this frame placed, moved, or deleted *)
  pasted : (int * int) list;  (* scene objects copied this frame: their networks follow *)
  opened : int option;  (* a node asked to be entered *)
  live_cook : bool;
  label : string;  (* names this frame's document change in history *)
}

type 'prepared t = {
  code_graph : Graph.t;
  presets : string;  (* preset directory *)
  name : string;  (* sketch name recorded in presets *)
  prompt : prompt option;
  notice : string option;
  doc : Document.t;  (* always the history's present *)
  level : Document.level;
  scene_level : bool;  (* false: one geometry object, no scene to go up to *)
  projections : projection Document.Layout.t;  (* per level; see [level_key] *)
  map_view : bool;  (* in the World, the view pane shows the lat-long map *)
  live_cook : bool;  (* cook while a drag holds the pointer *)
  rows : (Edit_graph.t * int * (float * float) Document.Layout.t
          * (Pxui_shell.Tree.row array * string list)) option;
  (* the list's rows, cached by network, display node, and tile layout *)
  factories : Edit_graph.factory list;  (* the SOP catalog *)
  graph_view : Pxui_graph.t;
  tree : Pxui_shell.Tree.t;
  ui : Pxui.Ui.t;
  workspace : Workspace.t;
  timeline : Sketch_support.Timeline.t;
  cook : 'prepared Cook.t;
  edit_error : string option;
  status_fps : int option;
  status_fps_at : float;
  history : Document.t Editor_core.History.t;
  focus : Workspace.column;
  pane_keys : (int * Workspace.column) list;
  leader : Leader.state;
  keymap : Leader.command list;
  timeline_frames : int;
  queued : Leader.action list;  (* picked in the palette, run next frame *)
}

type ('prepared, 'panel) update = {
  core : 'prepared t;
  effects : Parameter.effects;
  prepared_changed : bool;
  scene_changed : bool;  (* objects, lights, or the World changed: recompose *)
  framed : bounds option option;
  (** A framing request finished: [Some None] had no geometry. *)
  loaded_view : Yojson.Safe.t option;
  (** A preset loaded this frame; its environment view settings. *)
  actions : Leader.action list;
  panel : 'panel option;
  (* The frame without leader-consumed events, for the environment's own
     input handling. *)
  input : Frame.t;
}

let pane_ui bounds =
  let x, y, width, height = bounds in
  x + 8, y + 8, max 1 (width - 16), max 40 (height - 16)

(* The inspector column's kit panel. *)
let inspector_panel ui bounds build =
  let x, y, width, height = pane_ui bounds in
  Pxui.Ui.panel ui ~x:(float_of_int x) ~y:(float_of_int y)
    ~width:(float_of_int width) ~max_height:(float_of_int height)
    "workspace-inspector-panel" build

(* ---- levels ---- *)

let scene value = value.doc.Document.scene.graph

let kind value id = Option.map Node.operation (Edit_graph.find (scene value) ~node_id:id)

let level_key = function Document.Scene -> -1 | Inside id -> id

let catalog value = function
  | Document.Scene -> Objects.catalog @ [Layers.Settings.factory]
  | Inside id -> (match kind value id with
    | Some "geometry" -> value.factories
    | Some "world" -> Layers.catalog
    | Some _ | None -> [])

let network value = Option.get (Document.network value.doc value.level)
let document value = (network value).graph

let projection value =
  match Document.Layout.find_opt (level_key value.level) value.projections with
  | Some projection -> projection
  | None -> (match value.level with
    | Document.Scene -> List_view
    | Inside id when kind value id = Some "geometry" -> Graph_view
    | Inside _ -> List_view)

let enterable value id = match kind value id with
  | Some ("geometry" | "world") ->
      Document.Layout.mem id value.doc.Document.networks
  | Some _ | None -> false

(* A graph view of [level]'s network at the graph's default zoom ([Home]
   frames it all; framing large networks here would draw every tile). *)
let view_of value level (frame : Frame.t) =
  let network = Option.get (Document.network value.doc level) in
  let gx, gy, gw, gh = (Workspace.geometry value.workspace frame).graph in
  Pxui_graph.create_document ~x:gx ~y:gy ~width:(max 1 gw) ~height:(max 1 gh)
    ~catalog:(Pxui_graph.catalog_of_factories (catalog { value with level } level))
    ~flaggable:(fun info -> level = Document.Scene && info.Edit_graph.operation = "camera")
    network.graph
  |> Document.to_view network
  |> Pxui_graph.with_flagged (if level = Document.Scene then value.doc.active_camera else None)

let open_level value level frame =
  if level = value.level then value else
  let world = match level with
    | Document.Inside id -> kind value id = Some "world" | Scene -> false in
  { value with level; graph_view = view_of value level frame; map_view = world;
    tree = Pxui_shell.Tree.create () }

(* The geometry objects to cook: visible ones, each with its network. *)
let geometry_objects value =
  List.filter_map (fun id ->
    match Edit_graph.find (scene value) ~node_id:id,
        Document.Layout.find_opt id value.doc.Document.networks with
    | Some node, Some network when Objects.visible node ->
        Some (id, network.Document.graph, network.displayed)
    | _ -> None) (Objects.ids "geometry" (scene value))

(* The object the sketch-facing single-object accessors describe: the open
   one, else the first visible geometry object. *)
let focus_object value = match value.level with
  | Inside id when kind value id = Some "geometry" -> Some id
  | Inside _ | Scene ->
      Option.map (fun (id, _, _) -> id) (List.nth_opt (geometry_objects value) 0)

let pieces value = value.cook.Cook.pieces
let piece value = Option.bind (focus_object value) (fun id ->
    List.find_opt (fun (piece : _ Cook.piece) -> piece.id = id) (pieces value))

let prepared value = Option.map (fun (piece : _ Cook.piece) -> piece.prepared) (piece value)
let graph value = match Option.bind (focus_object value) (fun id ->
    List.assoc_opt id value.cook.Cook.graphs), piece value with
  | Some graph, _ -> graph
  | None, Some piece -> piece.graph
  | None, None -> value.code_graph
let displayed_node = graph
let settings value = value.doc.Document.settings
let timeline value = value.timeline
let selected_node value = Option.bind (Pxui_graph.selected value.graph_view)
    (fun node_id -> Edit_graph.find (document value) ~node_id)
let panes value frame = Workspace.geometry value.workspace frame
let column_visible value column = not (Workspace.collapsed value.workspace column)

(* The transform the open network's handles live in: an object's own when
   inside it, the selected object's parent chain at the scene level. *)
let space value = match value.level with
  | Inside id when kind value id = Some "geometry" -> Objects.world (scene value) id
  | Inside _ -> Mat4.identity
  | Scene -> (match Pxui_graph.selected value.graph_view with
    | Some id -> Objects.parent_world (scene value) id
    | None -> Mat4.identity)

(* ---- the graph as a list ---- *)

(* A row's kind letter and colour (the prototype's palette). *)
let badge operation =
  let hex = Color.hex_exn in
  match operation with
  | "geometry" -> "G", hex "#3f7a52" | "light" -> "L", hex "#b07a1c"
  | "camera" -> "C", hex "#5a4f86" | "world" -> "W", hex "#285f77"
  | "sun" -> "✦", hex "#b07a1c"
  | "gradient" | "sky" | "shape" | "scatter" | "room" -> "·", hex "#6d8a95"
  | _ -> "S", hex "#566463"

let scene_rows ?active document graph_view =
  let infos = Edit_graph.inspect document in
  let children = Hashtbl.create 16 in
  let x id = match Pxui_graph.node_position graph_view id with
    | Some (x, _) -> x | None -> 0. in
  List.iter (fun (info : Edit_graph.node_info) ->
    let parent = if Array.length info.inputs > 0 then info.inputs.(0) else None in
    Hashtbl.replace children parent
      (info :: Option.value ~default:[] (Hashtbl.find_opt children parent))) infos;
  let sorted parent = List.sort (fun (a : Edit_graph.node_info) b ->
      let order = Float.compare (x a.id) (x b.id) in
      if order <> 0 then order else Int.compare a.id b.id)
      (Option.value ~default:[] (Hashtbl.find_opt children parent)) in
  let rec emit depth (info : Edit_graph.node_info) =
    let flags = List.filter_map (fun name ->
        if Objects.has_flag name info.node then Some (Objects.flag name info.node) else None)
        ["visible"; "render"] in
    { Pxui_shell.Tree.id = info.id; depth; label = info.label;
      detail = (if active = Some info.id then "* render cam" else info.operation);
      badge = badge info.operation; link = false; ghost = false; flags }
    :: List.concat_map (emit (depth + 1)) (sorted (Some info.id)) in
  Array.of_list (List.concat_map (emit 0) (sorted None))

let trunk_rows document ~flags =
  Array.map (fun (id, depth, link) ->
    let node = Edit_graph.find document ~node_id:id in
    { Pxui_shell.Tree.id; depth; link; ghost = false;
      label = Option.fold ~none:"" ~some:Node.label node;
      detail = Option.fold ~none:"" ~some:Node.operation node;
      badge = badge (Option.fold ~none:"" ~some:Node.operation node);
      flags = Option.fold ~none:[] ~some:(flags id) node })
    (Pxui_graph.trunk document)

let rows value document graph_view = match value.level with
  | Document.Scene -> scene_rows ?active:value.doc.active_camera document graph_view,
      ["vis"; "rnd"]
  | Inside id when kind value id = Some "geometry" ->
      trunk_rows document ~flags:(fun node_id _ ->
        [node_id = Pxui_graph.viewed graph_view]), ["disp"]
  | Inside _ ->
      trunk_rows document ~flags:(fun _ node ->
        if Objects.has_flag "visible" node then [Objects.flag "visible" node] else []),
      ["vis"]

(* Rewire [ids] under [parent] (None: the scene root), keeping each one's
   world placement. *)
let reparent document ids parent =
  List.fold_left (fun document id ->
    let before = Objects.parent_world document id in
    let rewired = match parent with
      | Some parent when parent <> id ->
          Edit_graph.connect ~source:parent ~consumer:id ~input_index:0 document
      | Some _ -> Ok document
      | None when Objects.parent document id <> None ->
          Edit_graph.disconnect ~consumer:id ~input_index:0 document
      | None -> Ok document in
    match rewired with
    | Error _ -> document
    | Ok document ->
        (match Objects.keep_world document id ~before with
         | [] -> document
         | values -> (match Edit_graph.apply_parameters document ~node_id:id values with
           | Ok (document, _) -> document | Error _ -> document))) document ids

(* A layer chain in stack order, bottom first, with [ids] moved. *)
let restack document order =
  let document = List.fold_left (fun document id ->
      match Edit_graph.inputs document ~node_id:id with
      | Some inputs when Array.length inputs > 0 && inputs.(0) <> None ->
          Result.value ~default:document
            (Edit_graph.disconnect ~consumer:id ~input_index:0 document)
      | _ -> document) document order in
  let rec wire document = function
    | below :: (above :: _ as rest) ->
        wire (Result.value ~default:document
          (Edit_graph.connect ~source:below ~consumer:above ~input_index:0 document)) rest
    | [_] | [] -> document in
  wire document order

let apply_parameter document id name value =
  match Edit_graph.find document ~node_id:id with
  | Some node when Objects.has_flag name node ->
      (match Edit_graph.apply_parameters document ~node_id:id [name, value] with
       | Ok (document, _) -> document | Error _ -> document)
  | Some _ | None -> document

(* Tree intents become document edits, selection, or an entry request. *)
let apply_tree value (document, graph_view, tree, opened, label, rows) intent =
  let module T = Pxui_shell.Tree in
  let world = match value.level with
    | Document.Inside id -> kind value id = Some "world" | Scene -> false in
  let geometry = match value.level with
    | Document.Inside id -> kind value id = Some "geometry" | Scene -> false in
  let stack () = Array.to_list rows
    |> List.filter_map (fun (row : T.row) -> if row.link then None else Some row.id) in
  let restacked order =
    let document = restack document order in
    let top = List.nth order (List.length order - 1) in
    document, Pxui_graph.view top (Pxui_graph.with_document document graph_view),
    tree, opened, Some "Reorder layers", rows in
  let move_in order ids target drop =
    let rest = List.filter (fun id -> not (List.mem id ids)) order in
    List.concat_map (fun id ->
      if id <> target then [id]
      else match drop with
        | T.Before -> ids @ [id] | After | Inside -> id :: ids) rest in
  match intent with
  | T.Select ids ->
      document, (match ids with
        | [] -> Pxui_graph.clear_selection graph_view
        | ids -> Pxui_graph.select_nodes ids graph_view), tree, opened, label, rows
  | Flag { ids; column = _; value = on } when geometry ->
      (match List.rev ids with
       | id :: _ when on -> document, Pxui_graph.view id graph_view, tree, opened,
           Some "Display", rows
       | _ -> document, graph_view, tree, opened, label, rows)
  | Flag { ids; column; value = on } ->
      let name = List.nth (if world then ["visible"] else ["visible"; "render"]) column in
      let document = List.fold_left (fun document id ->
          apply_parameter document id name (Parameter.Bool_value on)) document ids in
      document, graph_view, tree, opened, Some (if on then "Show" else "Hide"), rows
  | Move { ids; target; drop } when world ->
      restacked (move_in (stack ()) ids target drop)
  | Move { ids; target; drop } when value.level = Document.Scene ->
      let parent = match drop with
        | T.Inside -> Some target
        | Before | After -> Objects.parent document target in
      let document = reparent document ids parent in
      (* Siblings list in tile order: place the moved tiles beside the target. *)
      let graph_view = match Pxui_graph.node_position graph_view target, drop with
        | Some (x, y), (T.Before | After) ->
            Pxui_graph.place_nodes (List.mapi (fun index id ->
              id, (if drop = Before then x -. 1. -. float_of_int index
                   else x +. 1. +. float_of_int index), y +. 60.) ids) graph_view
        | _ -> graph_view in
      document, Pxui_graph.with_document document graph_view, tree, opened,
      Some "Reparent", rows
  | Indent ids when value.level = Document.Scene ->
      (* Under the previous sibling row. *)
      let parent = match ids with
        | [] -> None
        | id :: _ ->
            let index = ref None in
            Array.iteri (fun k (row : T.row) -> if row.id = id && !index = None
              then index := Some k) rows;
            Option.bind !index (fun k ->
              let depth = rows.(k).depth in
              let found = ref None in
              for candidate = k - 1 downto 0 do
                if !found = None && rows.(candidate).depth = depth then
                  found := Some rows.(candidate).id
                else if rows.(candidate).depth < depth then found := Some (-1)
              done;
              match !found with Some id when id >= 0 -> Some id | _ -> None) in
      (match parent with
       | None -> document, graph_view, tree, opened, label, rows
       | Some parent ->
           let document = reparent document ids (Some parent) in
           document, Pxui_graph.with_document document graph_view, tree, opened,
           Some "Reparent", rows)
  | Outdent ids when value.level = Document.Scene ->
      let document = List.fold_left (fun document id ->
          match Objects.parent document id with
          | Some parent -> reparent document [id] (Objects.parent document parent)
          | None -> document) document ids in
      document, Pxui_graph.with_document document graph_view, tree, opened,
      Some "Reparent", rows
  | Reorder { ids; delta } when world ->
      let order = stack () in
      (match List.find_index (fun id -> List.mem id ids) order with
       | Some index ->
           let target = List.nth_opt (List.filter (fun id -> not (List.mem id ids)) order)
               (max 0 (index + delta)) in
           (match target with
            | Some target -> restacked (move_in order ids target
                (if delta < 0 then T.Before else After))
            | None -> document, graph_view, tree, opened, label, rows)
       | None -> document, graph_view, tree, opened, label, rows)
  | Reorder { ids; delta } when value.level = Document.Scene ->
      (* Siblings follow tile x: swap with the neighbour row at the same depth. *)
      let placed = List.filter_map (fun id ->
          Option.map (fun (x, y) -> id, x +. float_of_int delta *. 240., y)
            (Pxui_graph.node_position graph_view id)) ids in
      document, Pxui_graph.place_nodes placed graph_view, tree, opened,
      Some "Reorder", rows
  | Rename (id, name) ->
      (match Option.map (Node.relabel name) (Edit_graph.find document ~node_id:id) with
       | Some node -> (match Edit_graph.replace_node node document with
         | Ok document -> document, Pxui_graph.with_document document graph_view,
             tree, opened, Some "Rename", rows
         | Error _ -> document, graph_view, tree, opened, label, rows)
       | None -> document, graph_view, tree, opened, label, rows)
  | Activate id when geometry ->
      document, Pxui_graph.view id graph_view, tree, opened, Some "Display", rows
  | Activate id -> document, graph_view, tree, Some id, label, rows
  | Delete ids ->
      let document = Edit_graph.remove_nodes ids document in
      document, Pxui_graph.clear_selection (Pxui_graph.with_document document graph_view),
      tree, opened, Some "Delete", rows
  | Move _ | Indent _ | Outdent _ | Reorder _ ->
      document, graph_view, tree, opened, label, rows

(* ---- creation ---- *)

(* The document a sketch starts from: its code graph becomes the geometry
   object geo1 (camera SOPs in it move up to the scene as camera objects),
   plus [seed]'s additions to the scene. *)
let initial_doc ~settings ~seed_scene code_graph =
  let sop = Edit_graph.of_graph code_graph in
  let cameras = List.filter_map (fun (info : Edit_graph.node_info) ->
      if info.operation = "camera" then Some info.node else None)
      (Edit_graph.inspect sop) in
  let sop = Edit_graph.remove_nodes (List.map Node.id cameras) sop in
  let geometry = Result.get_ok (Edit_graph.instantiate_optional
      Objects.Geometry.factory [None]) |> Node.relabel "geo1" in
  let empty_scene = Result.get_ok (Edit_graph.add_node ~factory:Objects.Geometry.factory
      ~inputs:[|None|] geometry Edit_graph.empty) in
  let scene = List.fold_left (fun scene camera ->
      Result.value ~default:scene (Edit_graph.add_node camera scene))
      empty_scene cameras in
  let scene = seed_scene scene in
  let displayed = Option.value ~default:(Node.id code_graph) (Edit_graph.root sop) in
  let network graph displayed =
    { Document.graph; layout = Document.Layout.empty; displayed } in
  { Document.scene = network scene (Node.id geometry);
    networks = Document.Layout.singleton (Node.id geometry) (network sop displayed);
    active_camera = None; settings },
  Node.id geometry

(* A World object for [world], with its layer network. *)
let add_world (doc : Document.t) world =
  let _, values = Layers.of_world world in
  let ( let* ) = Result.bind in
  let* node = Edit_graph.instantiate Layers.Settings.factory [] in
  let* graph = Edit_graph.add_node ~factory:Layers.Settings.factory node doc.scene.graph in
  let* graph, _ = Edit_graph.apply_parameters graph ~node_id:(Node.id node) values in
  let* network = Layers.network_of_world world in
  Ok { doc with scene = { doc.scene with graph };
       networks = Document.Layout.add (Node.id node) network doc.networks }

(* A new World starts as a daylight sky with a sun, ready to turn. *)
let daylight = Option.value ~default:World.default (List.assoc_opt "daylight" World.presets)

let create ?(settings = Settings.none) ?(keymap = Leader.keymap)
    ?(seed_scene = fun _ scene -> scene) ?(scene_level = true) ?world
    ?(name = "sketch") ?presets ?(timeline_frames = 240)
    ?(layout = Pxui_shell.Layout.default) ?(factories = [])
    ?(seed = 0L) ?(grain = 16_384)
    ?domains ?(max_entries = 32)
    ?(max_payload_bytes = 256 * 1024 * 1024)
    ~graph ~prepare () =
  Result.map (fun cook ->
      let workspace = Workspace.create layout in
      let doc, geometry = initial_doc ~settings
          ~seed_scene:(seed_scene factories) graph in
      let doc = match Option.map (add_world doc) world with
        | Some (Ok doc) -> doc | Some (Error _) | None -> doc in
      let presets = match presets with
        | Some directory -> directory
        | None -> Filename.concat (Filename.concat
            (Option.value ~default:"." (Sys.getenv_opt "HOME")) ".prismel")
            (Preset.sanitize name) in
      let level = if scene_level then Document.Scene else Inside geometry in
      let value = { code_graph = graph; presets; name; prompt = None; notice = None;
        doc; level; scene_level; projections = Document.Layout.empty; map_view = false;
        rows = None; live_cook = true;
        factories;
        graph_view = Pxui_graph.create (Sop.points [||]);
        tree = Pxui_shell.Tree.create ();
        ui = Pxui.Ui.create (); workspace;
        timeline = Sketch_support.Timeline.create (); cook;
        edit_error = None; status_fps = None;
        status_fps_at = Float.neg_infinity;
        history = Editor_core.History.create doc;
        focus = Workspace.View; pane_keys = []; leader = Leader.Idle;
        keymap; timeline_frames = max 1 timeline_frames; queued = [] } in
      (* Record the laid-out positions of every network as the first state. *)
      let doc = List.fold_left (fun doc level ->
          let view = view_of { value with doc } level initial_frame in
          Document.with_network doc level
            (Document.of_view (Option.get (Document.network doc level)).graph view))
          doc (Document.Scene :: List.map (fun (id, _) -> Document.Inside id)
            (Document.Layout.bindings doc.networks)) in
      { value with doc; history = Editor_core.History.create doc;
        graph_view = view_of { value with doc } level initial_frame })
    (Cook.create ~prepare ~seed ~grain ?domains ~max_entries
      ~max_payload_bytes ())

let truncate limit text = if String.length text <= limit then text
  else String.sub text 0 (limit - 3) ^ "..."

let level_name value = match value.level with
  | Document.Scene -> "scene"
  | Inside id -> "scene › " ^ Option.fold ~none:"?" ~some:Node.label
      (Edit_graph.find (scene value) ~node_id:id)

let status_text value =
  let cook = match Cook.status value.cook with
    | Async_cook.Cooking { seconds; queued; _ } ->
        Printf.sprintf "Cooking… %.1fs%s" seconds
          (if queued then " · latest queued" else "")
    | Idle ->
        (match value.edit_error, value.cook.error, value.cook.seconds with
         | Some error, _, _ -> "Graph edit rejected: " ^ truncate 49 error
         | None, Some error, _ -> "Cook rejected: " ^ truncate 54 error
         | None, None, _ when value.notice <> None -> Option.get value.notice
         | None, None, Some seconds -> Printf.sprintf "Cook complete · %.3fs" seconds
         | None, None, None -> "Waiting for first cook") in
  (* What the open level's keys do, so the World and the menu are findable. *)
  let hint = match value.level with
    | Document.Scene when value.scene_level ->
        "i/double-click enter · Space a add · Space e World"
    | Scene -> ""
    | Inside id when kind value id = Some "world" ->
        "u up · drag map: move layer/sun · e dome/light · [ ] time · Space l 3D/map"
    | Inside _ when value.scene_level -> "u up · Space a add · Space l list/graph"
    | Inside _ -> "Space a add · Space l list/graph" in
  cook ^ " · " ^ level_name value ^ (if hint = "" then "" else " · " ^ hint)

(* The status strip under the view: kit text on a dark bar. *)
let status_box value ui (frame : Frame.t) ~render_status =
  let x, y, width, height = (Workspace.geometry value.workspace frame).status in
  if height > 0 then begin
    let text = truncate (max 1 ((width - 80) / 7))
        (status_text value ^ match render_status with
          | None -> "" | Some status -> " · " ^ status) in
    Pxui_shell.Status_bar.draw ui ~bounds:(x, y, width, height)
      ~text ~fps:value.status_fps
  end

(* Leader actions owned by the workspace; the environment handles the rest
   from [update.actions]. *)
let apply_action value (frame : Frame.t) (workspace, graph_view, tree, timeline, changes) action =
  let module T = Sketch_support.Timeline in
  let timeline_step step = let timeline, more = step timeline in
    workspace, graph_view, tree, timeline, changes @ more in
  let pointer () =
    let gx, gy, gw, gh = (Workspace.geometry workspace frame).graph in
    let mx, my = frame.mouse in
    if mx >= float gx && my >= float gy && mx < float (gx + gw) && my < float (gy + gh)
    then int_of_float mx, int_of_float my
    else gx + (gw / 3), gy + (gh / 3) in
  match action with
  | Leader.Toggle_timeline ->
      Workspace.toggle Workspace.Timeline workspace, graph_view, tree, timeline, changes
  | Toggle_graph ->
      Workspace.toggle Workspace.Graph workspace, graph_view, tree, timeline, changes
  | Toggle_inspector ->
      Workspace.toggle Workspace.Inspector workspace, graph_view, tree, timeline, changes
  | Open_camera ->
      Workspace.expand Workspace.Inspector workspace,
      Pxui_graph.clear_selection graph_view, tree, timeline, changes
  | Play_pause -> timeline_step T.toggle_pause
  | Reset -> timeline_step T.reset
  | Stop -> timeline_step T.stop
  | Add_node ->
      Workspace.expand Workspace.Graph workspace,
      Pxui_graph.open_menu_at (pointer ()) graph_view, tree, timeline, changes
  | Layout -> workspace, Pxui_graph.optimize_layout graph_view, tree, timeline, changes
  | Frame_tile when projection value = List_view ->
      workspace, graph_view, Pxui_shell.Tree.reveal tree, timeline, changes
  | Frame_tile -> workspace, Pxui_graph.frame_viewed graph_view, tree, timeline, changes
  | World_play when Sketch_support.Timeline.mode timeline <> Sketch_support.Timeline.Playing ->
      timeline_step T.toggle_pause
  | Hide_ui | Look_through | Fly | Save_preset | Browse_presets
  | Graph_command _ | List_command _ | Frame_camera | Undo | Redo | Command_palette
  | Sketch_command _ | Toggle_projection | Enter | Up | Go_world | Tool _
  | World_emit | World_reseed | World_time _ | World_play | World_preset _ ->
      workspace, graph_view, tree, timeline, changes

(* The undo label a graph intent gives its document change. *)
let intent_label = function
  | Pxui_graph.Connect_requested _ -> Some "Connect"
  | Disconnect_requested _ -> Some "Disconnect"
  | Delete_nodes_requested _ -> Some "Delete"
  | Add_requested _ -> Some "Add node"
  | Insert_requested _ -> Some "Insert node"
  | Paste_requested _ -> Some "Paste"
  | Viewed _ -> Some "Display"
  | Flag_requested _ -> Some "Set active camera"
  | Node_moved _ | Nodes_moved _ -> Some "Move"
  | Selected _ | View_changed | Connection_selected _ | Frame_camera_requested _
  | Open_requested _ -> None

let in_world value = match value.level with
  | Document.Inside id -> kind value id = Some "world" | Scene -> false

(* World keys: edit the selected layer, or the World node in the scene. *)
let world_keys value (doc : Document.t) graph_view actions =
  let world_id = match value.level with Inside id -> Some id | Scene -> None in
  let edit_layer f label (doc, _) = match world_id, Pxui_graph.selected graph_view with
    | Some id, Some layer ->
        (match Document.network doc (Inside id) with
         | Some network ->
             (match Option.bind (Edit_graph.find network.graph ~node_id:layer) f with
              | Some values ->
                  (match Edit_graph.apply_parameters network.graph ~node_id:layer values with
                   | Ok (graph, _) ->
                       Document.with_network doc (Inside id) { network with graph }, Some label
                   | Error _ -> doc, None)
              | None -> doc, None)
         | None -> doc, None)
    | _ -> doc, None in
  let edit_world f label (doc, _) = match world_id with
    | Some id ->
        (match Option.bind (Edit_graph.find doc.Document.scene.graph ~node_id:id) f with
         | Some values ->
             (match Edit_graph.apply_parameters doc.scene.graph ~node_id:id values with
              | Ok (graph, _) -> { doc with scene = { doc.scene with graph } }, Some label
              | Error _ -> doc, None)
         | None -> doc, None)
    | None -> doc, None in
  let field name node = List.find_map (fun (field : Parameter.field_view) ->
      if field.name = name then Some field.current else None) (Node.parameter_fields node) in
  List.fold_left (fun state -> function
    | Leader.World_emit -> edit_layer (fun node -> match field "emit" node with
        | Some (Parameter.Choice_value "Light") -> Some ["emit", Parameter.Choice_value "Dome"]
        | Some (Parameter.Choice_value _) -> Some ["emit", Parameter.Choice_value "Light"]
        | _ -> None) "Dome / light" state
    | World_reseed -> edit_layer (fun node -> match field "seed" node with
        | Some (Parameter.Int_value seed) -> Some ["seed", Parameter.Int_value (seed + 1)]
        | _ -> None) "Reseed" state
    | World_time delta -> edit_world (fun node -> match field "time_of_day" node with
        | Some (Parameter.Float_value hours) ->
            Some ["time_of_day", Parameter.Float_value
              (Float.max 0. (Float.min 24. (hours +. delta)))]
        | _ -> None) "Time of day" state
    | World_play -> edit_world (fun node -> match field "day_cycle" node with
        | Some (Parameter.Float_value 0.) -> Some ["day_cycle", Parameter.Float_value 1.]
        | _ -> None) "Day cycle" state
    | World_preset index ->
        (match world_id, List.nth_opt World.presets index with
         | Some id, Some (name, world) ->
             let doc, _ = state in
             (match Layers.network_of_world world, Edit_graph.apply_parameters
                  doc.scene.graph ~node_id:id (snd (Layers.of_world world)) with
              | Ok network, Ok (graph, _) ->
                  { (Document.with_network doc (Inside id) network) with
                    scene = { doc.scene with graph } }, Some ("Preset " ^ name)
              | _ -> state)
         | _ -> state)
    | _ -> state) (doc, None) actions

(* Commands that only mean something on this level and projection. *)
let routed value =
  let graph_shown = not (Workspace.collapsed value.workspace Workspace.Graph) in
  let listing = projection value = List_view in
  List.filter (fun (command : Leader.command) -> match command.action with
    | List_command _ -> listing && graph_shown
    | Graph_command Pxui_graph.Frame_all -> not listing && graph_shown
    | Graph_command _ | Frame_camera -> graph_shown
    | Enter | Up | Go_world -> value.scene_level
    | World_emit | World_reseed | World_time _ | World_play | World_preset _ ->
        in_world value
    | _ -> true) value.keymap

(* A geometry object added in the scene gets a network with one box, a
   World its default layers. *)
let seed_networks value doc added =
  List.fold_left (fun doc id ->
    if Document.Layout.mem id doc.Document.networks then doc
    else match Option.map Node.operation (Edit_graph.find doc.Document.scene.graph ~node_id:id) with
      | Some "geometry" ->
          let box = List.find_opt (fun factory ->
              Edit_graph.factory_arity factory = 0) (List.filter (fun factory ->
              Edit_graph.factory_key factory = "box") value.factories
              @ value.factories) in
          (match Option.map (fun factory ->
              Result.bind (Edit_graph.instantiate factory []) (fun node ->
                Result.map (fun graph -> graph, node)
                  (Edit_graph.add_node ~factory node Edit_graph.empty))) box with
           | Some (Ok (graph, node)) ->
               { doc with networks = Document.Layout.add id
                   { Document.graph; layout = Document.Layout.empty;
                     displayed = Node.id node } doc.networks }
           | Some (Error _) | None -> doc)
      | Some "world" ->
          (match Layers.network_of_world daylight with
           | Ok network -> { doc with networks = Document.Layout.add id network doc.networks }
           | Error _ -> doc)
      | Some _ | None -> doc) doc added

let update value ~all_ui_visible ~text_focus ~camera_panel ~view_handles
    ~render_status ~view_state (frame : Frame.t) =
  let text_focus = text_focus || value.prompt <> None
    || Pxui_shell.Tree.editing value.tree in
  let focus = if all_ui_visible then
      match Pxui.Ui.last_press_within value.ui frame
          (List.map fst value.pane_keys) with
      | Some key -> Option.value ~default:value.focus
          (List.assoc_opt key value.pane_keys)
      | None -> value.focus
    else value.focus in
  let keymap = routed value in
  let keymap = if all_ui_visible then keymap else List.filter (fun command ->
      match command.Editor_core.Command.action with
      | Leader.Graph_command _ | Leader.List_command _ | Leader.Frame_camera -> false
      | _ -> true) keymap in
  let leader, actions, frame = Editor_core.Router.step keymap ~focus ~text_focus ~frame
      value.leader in
  let actions = value.queued @ actions in
  let sample_fps = frame.time < value.status_fps_at
    || frame.time -. value.status_fps_at >= 1. in
  let status_fps, status_fps_at = if not sample_fps then
      value.status_fps, value.status_fps_at
    else (if frame.fps > 0. && Float.is_finite frame.fps
      then Some (int_of_float (Float.round frame.fps)) else None), frame.time in
  let shortcut_frame = if text_focus then
      { frame with Frame.events = List.filter (function
        | Event.KeyPressed _ | Event.KeyReleased _ | Event.TextInput _
        | Event.TextEditing _ -> false | _ -> true) frame.events }
    else frame in
  let timeline, timeline_changes = Sketch_support.Timeline.update
      value.timeline shortcut_frame in
  let workspace, graph_view, tree, timeline, timeline_changes = List.fold_left
      (apply_action value frame)
      (value.workspace, value.graph_view, value.tree, timeline, timeline_changes) actions in
  let graph_shown = all_ui_visible && not (Workspace.collapsed workspace Workspace.Graph) in
  let graph_view, command_changes = List.fold_left (fun (graph_view, changes) ->
    function
    | Leader.Graph_command command when graph_shown ->
        let graph_view, emitted = Pxui_graph.run_command graph_view command in
        graph_view, changes @ emitted
    | _ -> graph_view, changes) (graph_view, []) actions in
  let document = document value in
  let listing = projection value = List_view in
  let rows_cache = match value.rows with
    | Some (source, viewed, layout, rows) when listing && source == document
        && viewed = Pxui_graph.viewed graph_view && layout == (network value).layout ->
        Some (source, viewed, layout, rows)
    | _ when listing -> Some (document, Pxui_graph.viewed graph_view, (network value).layout,
        rows value document graph_view)
    | _ -> None in
  let rows, columns = match rows_cache with
    | Some (_, _, _, rows) -> rows | None -> [||], [] in
  let selected () = Pxui_graph.selected_nodes graph_view
    |> List.sort (fun a b -> if Some a = Pxui_graph.selected graph_view then -1
      else if Some b = Pxui_graph.selected graph_view then 1 else Int.compare a b) in
  let tree, list_intents = List.fold_left (fun (tree, intents) -> function
    | Leader.List_command command when graph_shown ->
        let tree, emitted = Pxui_shell.Tree.run_command tree rows
            ~selected:(selected ()) command in
        tree, intents @ emitted
    | _ -> tree, intents) (tree, []) actions in
  let initial_frame_request = if List.mem Leader.Frame_camera actions
    then Some (Pxui_graph.viewed graph_view) else None in
  let build ui =
    let workspace = Workspace.update workspace ui shortcut_frame in
    let panes = Workspace.geometry workspace frame in
    let root column bounds =
      column, Pxui_shell.Chrome.pane_root ui frame ~bounds
        ("workspace-pane-" ^ Leader.pane_name column) in
    let vx, vy, vw, _ = panes.view in
    let _, sy, _, sh = panes.status in
    let view, view_root = root Workspace.View (vx, vy, vw, sy + sh - vy) in
    let graph, graph_root = root Workspace.Graph panes.graph in
    let inspector_column, inspector_root =
      root Workspace.Inspector panes.inspector in
    let timeline_column, timeline_root =
      root Workspace.Timeline panes.timeline in
    let gx, gy, gw, gh = panes.graph in
    let graph_view = graph_view
      |> Pxui_graph.with_bounds ~x:gx ~y:gy ~width:(max 1 gw) ~height:(max 1 gh)
      |> Pxui_graph.with_visible
           (projection value = Graph_view
            && not (Workspace.collapsed workspace Workspace.Graph)) in
    let graph_view, graph_changes =
      if not (Workspace.collapsed workspace Workspace.Graph)
      then Pxui.Ui.within ui graph_root (fun () ->
        Pxui_graph.update graph_view ui shortcut_frame)
      else graph_view, [] in
    let tree, list_intents =
      if projection value = List_view
          && not (Workspace.collapsed workspace Workspace.Graph) then
        let tree, emitted = Pxui.Ui.within ui graph_root (fun () ->
          Pxui_shell.Tree.update tree ui shortcut_frame ~bounds:panes.graph
            ~title:(level_name value) ~columns rows
            ~selected:(selected ())) in
        tree, list_intents @ emitted
      else tree, list_intents in
    let graph_changes = command_changes @ graph_changes in
    let frame_request = List.fold_left (fun request -> function
      | Pxui_graph.Frame_camera_requested id -> Some id
      | _ -> request) initial_frame_request graph_changes in
    let opened = List.fold_left (fun opened -> function
      | Pxui_graph.Open_requested id -> Some id
      | _ -> opened) None graph_changes in
    let document, graph_view, edit_error, editor_effects, placed, pasted = List.fold_left
        (Doc.apply (catalog value value.level))
        (document, graph_view, value.edit_error, Parameter.no_effects, [], [])
        graph_changes in
    let tree_document = document in
    let document, graph_view, tree, opened, tree_label, _ = List.fold_left
        (apply_tree value) (document, graph_view, tree, opened, None, rows) list_intents in
    let placed = List.concat_map (function
      | Pxui_shell.Tree.Move { ids; _ } | Reorder { ids; _ } -> ids
      | _ -> []) list_intents @ placed in
    (* New rows open in rename mode in the list: type a name, or Enter on
       a blank one keeps the default. *)
    let tree = match List.find_map (function
        | Pxui_graph.Add_requested _ -> Pxui_graph.selected graph_view
        | _ -> None) graph_changes with
      | Some id when projection value = List_view -> Pxui_shell.Tree.rename id "" tree
      | _ -> tree in
    (* Only a geometry network cooks SOPs: an object, light, camera, or World
       edit is view work, never a re-cook. *)
    let node_effects effects = match value.level with
      | Document.Inside id when kind value id = Some "geometry" -> effects
      | Inside _ | Scene -> { effects with Parameter.cook = false } in
    let inspector_visible = not (Workspace.collapsed workspace Workspace.Inspector) in
    let selected = Option.bind (Pxui_graph.selected graph_view)
        (fun node_id -> Edit_graph.find document ~node_id) in
    let touched = tree_document != document || List.exists (function
      | Pxui_graph.Selected _ | View_changed | Connection_selected _
      | Frame_camera_requested _ | Open_requested _ -> false
      | _ -> true) graph_changes in
    let unchanged = value.doc.settings in
    let live = ref value.live_cook in
    let panel, document, parameter_effects, edit_error, settings =
      Pxui.Ui.within ui inspector_root (fun () -> match selected with
      | None when not inspector_visible ->
          None, document, Parameter.no_effects, edit_error, unchanged
      | None ->
          (* Sketch settings above the environment's camera/render panel. *)
          let edited, panel = inspector_panel ui panes.inspector (fun () ->
            live := Pxui.Ui.toggle ui "Live update while dragging" value.live_cook;
            let edited = match Settings.fields unchanged with
              | [] -> Ok (unchanged, Parameter.no_effects)
              | fields ->
                  Pxui.Ui.scope ui "sketch-settings" (fun () ->
                    Pxui.Ui.label ui "Settings";
                    match Pxui_shell.Inspector.fields ui fields with
                    | [] -> Ok (unchanged, Parameter.no_effects)
                    | changes -> Settings.apply unchanged changes) in
            edited, camera_panel ()) in
          (match edited with
           | Error message ->
               Some panel, document, Parameter.no_effects, Some message, unchanged
           | Ok (settings, effects) -> Some panel, document, effects, edit_error, settings)
      | Some _ when not inspector_visible ->
          None, document, Parameter.no_effects, edit_error, unchanged
      | Some node ->
          match inspector_panel ui panes.inspector (fun () ->
              Pxui.Ui.scope ui (Printf.sprintf "node.%d" (Node.id node)) (fun () ->
                Pxui.Ui.label ui (Node.label node);
                match Pxui_shell.Inspector.fields ui ~expanded:(expanded_folders node)
                    (Node.parameter_fields node) with
                | [] -> Ok (node, Parameter.no_effects)
                | changes -> Node.apply_parameters node changes)) with
          | Error message -> None, document, Parameter.no_effects, Some message, unchanged
          | Ok (edited, _) when edited == node ->
              None, document, Parameter.no_effects, edit_error, unchanged
          | Ok (edited, effects) ->
              (match Edit_graph.replace_node edited document with
               | Error message ->
                   None, document, Parameter.no_effects, Some message, unchanged
               | Ok document -> None, document, (node_effects effects), edit_error, unchanged)) in
    let timeline_intents = if Workspace.collapsed workspace Workspace.Timeline
      then [] else Pxui.Ui.within ui timeline_root (fun () ->
        Pxui_shell.Timeline_bar.draw ui ~bounds:panes.timeline
          ~playing:(Sketch_support.Timeline.mode timeline = Sketch_support.Timeline.Playing)
          ~frame:(Sketch_support.Timeline.frame timeline)
          ~time:(Sketch_support.Timeline.time timeline)
          ~max_frame:value.timeline_frames) in
    let handle_edits, grab, picked =
      if Workspace.collapsed workspace Workspace.View then [], false, None
      else Pxui.Ui.within ui view_root (fun () ->
        view_handles ui ~selected ~space:(space { value with graph_view })
          ~bounds:panes.view) in
    let graph_view = match picked with
      | Some id when value.level = Document.Scene -> Pxui_graph.select id graph_view
      | Some _ | None -> graph_view in
    let document, handle_effects = match selected, handle_edits with
      | Some node, _ :: _ ->
          (match Edit_graph.apply_parameters document ~node_id:(Node.id node)
              handle_edits with
           | Ok edited -> edited
           | Error _ -> document, Parameter.no_effects)
      | _ -> document, Parameter.no_effects in
    Pxui.Ui.within ui view_root (fun () ->
      status_box { value with workspace; status_fps } ui frame ~render_status);
    let roots = [view, view_root; graph, graph_root;
      inspector_column, inspector_root; timeline_column, timeline_root] in
    let focus = List.fold_left (fun (latest, focus) (column, box) ->
      match (Pxui.Ui.signal ui box).subtree_press with
      | Some index when index >= latest -> index, column
      | _ -> latest, focus) (-1, focus) roots
      |> snd in
    let pane_keys = List.map (fun (column, box) -> Pxui.Ui.key box, column)
      roots in
    (* The focused pane's accent outline. *)
    let bounds = match focus with
      | Workspace.View -> panes.view | Graph -> panes.graph
      | Inspector -> panes.inspector | Timeline -> panes.timeline in
    Pxui_shell.Chrome.focus ui ~bounds;
    { workspace; focus; pane_keys; graph_view; tree; document; edit_error;
      effects = Parameter.union_effects (node_effects editor_effects)
          (Parameter.union_effects parameter_effects (node_effects handle_effects));
      timeline_intents; frame_request; prompt = None; prompt_intent = None;
      panel; grab; settings; touched; placed; pasted; opened; live_cook = !live;
      label = (match List.find_map intent_label graph_changes, tree_label with
        | Some label, _ | None, Some label -> label
        | None, None when settings != unchanged -> "Settings"
        | None, None -> (match selected with
          | Some node -> "Edit " ^ Node.label node | None -> "Edit")) } in
  let leader_panel = match leader with
    | Leader.Pending prefix -> Some (fun ui ->
        Pxui_shell.Which_key.panel ui keymap ~prefix ~focus
          ~focus_name:(Leader.pane_name focus))
    | Idle -> None in
  (* Presets: Space s names and saves the document, Space b browses, loads
     (Enter), and deletes (Delete twice). A load replaces the document below
     as one undo entry. *)
  let initial_prompt = List.fold_left (fun prompt -> function
    | Leader.Save_preset -> Some (Saving (Preset.default_name ()))
    | Browse_presets ->
        Some (Browsing { query = ""; presets = Preset.list ~directory:value.presets })
    | Command_palette -> Some (Palette "")
    | _ -> prompt) value.prompt actions in
  let prompt_panel ui prompt =
    let module Ui = Pxui.Ui in
    let next = match prompt with
    | None -> None, None
    | Some (Saving name) ->
        (match Pxui_shell.Prompt.name ui ~key:"preset-save"
            ~title:"Save preset" ~label:"Preset name" ~query:name with
         | None | Some (_, `Cancel) -> None, None
         | Some (name, `Submit) -> None, Some (Save_preset_file name)
         | Some (name, _) -> Some (Saving name), None)
    | Some (Browsing { query; presets }) ->
        let rows query = List.filter (fun (name, _) -> Ui.fuzzy_match ~query name) presets
          |> List.map (fun (name, time) ->
            let tm = Unix.localtime time in
            name, Printf.sprintf "%02d-%02d %02d:%02d" (tm.tm_mon + 1) tm.tm_mday
              tm.tm_hour tm.tm_min) |> Array.of_list in
        (match Pxui_shell.Prompt.search ui ~key:"preset-browse"
            ~title:(Printf.sprintf "Presets · %d" (List.length presets))
            ~label:"Search presets" ~query ~rows with
         | None | Some (_, `Cancel) -> None, None
         | Some (query, `Pick index) ->
             let name = fst (rows query).(index) in
             None, Some (Load_preset_file name)
         | Some (query, `Delete index) ->
             let name = fst (rows query).(index) in
             Some (Browsing { query; presets }),
             Some (Delete_preset_file { name; query })
         | Some (query, _) -> Some (Browsing { query; presets }), None)
    | Some (Palette query) ->
        (* Every keymap command once per id (undo has several chords). *)
        let commands = List.fold_left (fun seen (command : Leader.command) ->
            if List.exists (fun (c : Leader.command) -> c.id = command.id) seen then seen
            else command :: seen) [] keymap |> List.rev in
        let matches query = List.filter (fun (c : Leader.command) ->
            Ui.fuzzy_match ~query c.label) commands in
        let rows query = Array.of_list (List.map (fun (c : Leader.command) -> c.label, "")
            (matches query)) in
        (match Pxui_shell.Prompt.search ui ~key:"command-palette"
            ~title:"Commands" ~label:"Search commands" ~query ~rows with
         | None | Some (_, `Cancel) -> None, None
         | Some (query, `Pick index) ->
             None, Some (Run_action (List.nth (matches query) index).action)
         | Some (query, _) -> Some (Palette query), None) in
    (* A closed prompt must not keep keyboard focus into the next frame. *)
    if fst next = None && value.prompt <> None then Ui.unfocus ui;
    next in
  let result = match Pxui_shell.Shell.frame value.ui frame
      ~visible:all_ui_visible ~overlay:leader_panel
      ~body:(fun ui ->
        let result = build ui in
        let prompt, prompt_intent = prompt_panel ui initial_prompt in
        { result with prompt; prompt_intent }) with
    | Some result -> result
    | None ->
      { workspace; focus; pane_keys = []; graph_view; tree; document;
        edit_error = value.edit_error;
        effects = Parameter.no_effects; timeline_intents = [];
        frame_request = initial_frame_request; prompt = initial_prompt;
        prompt_intent = None; panel = None; grab = false;
        settings = value.doc.settings; touched = false; placed = []; pasted = [];
        opened = None; live_cook = value.live_cook; label = "Edit" } in
  let timeline, timeline_changes = List.fold_left (fun (timeline, changes) intent ->
    let next, emitted = match intent with
      | Pause_toggle -> Sketch_support.Timeline.toggle_pause timeline
      | Stop_playback -> Sketch_support.Timeline.stop timeline
      | Reset_playback -> Sketch_support.Timeline.reset timeline
      | Seek_playback frame -> Sketch_support.Timeline.seek timeline ~frame in
    next, changes @ emitted) (timeline, timeline_changes) result.timeline_intents in
  let prompt, notice, loaded = match result.prompt_intent with
    | None -> result.prompt, value.notice, None
    | Some (Run_action _) -> result.prompt, value.notice, None
    | Some (Save_preset_file name) ->
        let notice = match Preset.save ~directory:value.presets ~name
            ~sketch:value.name ~doc:value.doc ~view:(view_state result.panel) with
          | Ok path -> "Saved preset " ^ Filename.basename path
          | Error message -> "Preset not saved: " ^ message in
        result.prompt, Some notice, None
    | Some (Load_preset_file name) ->
        (match Preset.load ~path:(Preset.path ~directory:value.presets ~name)
            ~code:value.code_graph ~factories:value.factories
            ~settings:value.doc.settings with
         | Ok preset -> result.prompt, Some ("Loaded preset " ^ name), Some preset
         | Error message -> result.prompt, Some ("Preset rejected: " ^ message), None)
    | Some (Delete_preset_file { name; query }) ->
        let notice = match Preset.delete ~directory:value.presets ~name with
          | Ok () -> "Deleted preset " ^ name
          | Error message -> "Preset not deleted: " ^ message in
        Some (Browsing { query; presets = Preset.list ~directory:value.presets }),
        Some notice, None in
  (* Shared undo stack: every document change (graph edits, node creation,
     paste, inspector commits) becomes one history entry; Command/Ctrl-Z
     undoes, Shift-Command/Ctrl-Z or Ctrl-Y redoes. An edit frame re-reads
     only the tiles it placed; a preset load or automatic layout moves every
     tile and takes a whole snapshot. *)
  let present = value.doc in
  let laid_out = List.mem Leader.Layout actions in
  let current = network value in
  let next = match loaded with
    | Some (preset : Preset.loaded) -> preset.doc
    | None ->
        let edited = if laid_out
          then Document.of_view result.document result.graph_view
          else if result.document == current.graph && not result.touched then current
          else Document.edit current result.document result.graph_view result.placed in
        let doc = if edited == current then present
          else Document.with_network present value.level edited in
        let doc = if value.level = Document.Scene && edited != current then
            seed_networks value (Document.prune (Document.copy_networks doc result.pasted))
              (List.map (fun (info : Edit_graph.node_info) -> info.id)
                (Edit_graph.inspect edited.graph))
          else doc in
        let active_camera = if value.level = Document.Scene
          then Pxui_graph.flagged result.graph_view else doc.active_camera in
        let doc = if active_camera = doc.active_camera then doc
          else { doc with active_camera } in
        if result.settings == doc.settings then doc
        else { doc with settings = result.settings } in
  let next, world_label = if in_world value
    then world_keys value next result.graph_view actions else next, None in
  (* Space e opens the World, creating the singleton on first use. *)
  let next, world_added = match Objects.ids "world" next.scene.graph with
    | [] when List.mem Leader.Go_world actions && value.scene_level ->
        (match add_world next daylight with Ok doc -> doc, true | Error _ -> next, false)
    | _ -> next, false in
  let dragging = Frame.mouse_down Input.LeftButton frame in
  let history = if next == present then value.history
    else Editor_core.History.record
        ~label:(if Option.is_some loaded then "Load preset"
          else if world_added then "Add World"
          else if world_label <> None then Option.get world_label
          else if laid_out then "Layout" else result.label)
        ~merge:(if dragging then Gesture 0 else Step) next value.history in
  let ended_gesture = Frame.has_event (function
    | Event.MouseReleased (Input.LeftButton, _) | Event.WindowFocusLost -> true
    | _ -> false) frame in
  let history = if ended_gesture then Editor_core.History.seal history else history in
  let stepped = if List.mem Leader.Redo actions then Editor_core.History.redo history
    else if List.mem Leader.Undo actions then Editor_core.History.undo history else None in
  let notice = match stepped with
    | None -> notice
    | Some _ when List.mem Leader.Redo actions ->
        Option.map (fun label -> "Redo " ^ label) (Editor_core.History.redo_label history)
    | Some _ -> Some ("Undo " ^ Editor_core.History.label history) in
  let history, doc, undone = match stepped with
    | Some history -> history, Editor_core.History.present history, true
    | None -> history, Editor_core.History.present history, false in
  let effects = if undone || Option.is_some loaded
    then Parameter.union_effects result.effects Doc.cook_effects else result.effects in
  (* The open level must still exist after undo or a preset load. *)
  let level = match value.level with
    | Inside id when Option.is_none loaded && Document.Layout.mem id doc.networks
        && Edit_graph.find doc.scene.graph ~node_id:id <> None -> value.level
    | Inside _ when not value.scene_level ->
        (match Objects.ids "geometry" doc.scene.graph with
         | id :: _ -> Document.Inside id | [] -> value.level)
    | Inside _ | Scene -> if value.scene_level then Document.Scene else value.level in
  let value' = { value with doc; level; workspace = result.workspace } in
  let graph_view = if level <> value.level then view_of value' level frame
    else if undone || Option.is_some loaded then
      Document.to_view (network value') result.graph_view
      |> Pxui_graph.with_flagged (if level = Document.Scene then doc.active_camera else None)
    else
      let network = network value' in
      Pxui_graph.with_document network.graph result.graph_view
      |> Pxui_graph.with_flagged (if level = Document.Scene then doc.active_camera else None)
      |> fun view -> if Pxui_graph.viewed view = network.displayed
          || Edit_graph.find network.graph ~node_id:network.displayed = None then view
        else Pxui_graph.view network.displayed view in
  (* Entering and leaving levels: i / double-click / list activation, u. *)
  let target = match List.find_opt (function
      | Leader.Enter | Up | Go_world -> true | _ -> false) actions, result.opened with
    | Some Leader.Up, _ -> (match level with
      | Inside _ when value.scene_level -> Some Document.Scene | _ -> None)
    | Some Leader.Go_world, _ ->
        Option.map (fun id -> Document.Inside id)
          (List.find_opt (enterable value') (Objects.ids "world" doc.scene.graph))
    | Some Leader.Enter, _ | _, Some _ ->
        let candidate = match result.opened with
          | Some id -> Some id | None -> Pxui_graph.selected graph_view in
        (match level, candidate with
         | Document.Scene, Some id when enterable value' id -> Some (Document.Inside id)
         | _ -> None)
    | _ -> None in
  let value' = { value' with graph_view; tree = result.tree } in
  let value' = match target with
    | Some level -> open_level value' level frame
    | None -> value' in
  (* In the World, Space l flips the view pane to the lat-long map. *)
  let map_view = if List.mem Leader.Toggle_projection actions && in_world value'
    then not value'.map_view else value'.map_view && in_world value' in
  let value' = { value' with map_view } in
  let projections = if List.mem Leader.Toggle_projection actions && not (in_world value') then
      Document.Layout.add (level_key value'.level)
        (if projection value' = List_view then Graph_view else List_view) value'.projections
    else value'.projections in
  (* Switching to the graph frames it, so its tiles are on screen. *)
  let graph_view = if projection { value' with projections } = Graph_view
      && projection value' = List_view
    then fst (Pxui_graph.run_command value'.graph_view Pxui_graph.Frame_all)
    else value'.graph_view in
  let value' = { value' with projections; rows = rows_cache; graph_view;
    live_cook = result.live_cook } in
  let frame_request = match result.frame_request, value'.level with
    | Some node, Inside id when kind value' id = Some "geometry" -> Some (id, node)
    | _ -> None in
  let cooked = Cook.update ~live:result.live_cook value.cook ~settings:doc.settings
      ~objects:(geometry_objects value') ~edit_error:result.edit_error ~effects
      ~timeline_changes ~timeline ~frame ~frame_request in
  (* Framing: local bounds move into the world with their object; at the
     scene level [F] frames every cooked object. *)
  let lower (a : Vec3.t) (b : Vec3.t) =
    Vec3.create (Float.min a.x b.x) (Float.min a.y b.y) (Float.min a.z b.z)
  and upper (a : Vec3.t) (b : Vec3.t) =
    Vec3.create (Float.max a.x b.x) (Float.max a.y b.y) (Float.max a.z b.z) in
  let world_bounds id (lo, hi) =
    let matrix = Objects.world doc.scene.graph id in
    let corners = List.init 8 (fun index ->
      Mat4.transform_point matrix (Vec3.create
        (if index land 1 = 0 then lo.Vec3.x else hi.Vec3.x)
        (if index land 2 = 0 then lo.y else hi.y)
        (if index land 4 = 0 then lo.z else hi.z))) in
    List.fold_left (fun (lo, hi) point -> lower lo point, upper hi point)
      (List.hd corners, List.hd corners) corners in
  let framed = match cooked.framed, frame_request with
    | Some (Some bounds), Some (id, _) -> Some (Some (world_bounds id bounds))
    | framed, _ when List.mem Leader.Frame_camera actions && value'.level = Document.Scene ->
        ignore framed;
        Some (List.fold_left (fun union (piece : _ Cook.piece) ->
          match piece.bounds, union with
          | None, union -> union
          | Some bounds, None -> Some (world_bounds piece.id bounds)
          | Some bounds, Some (lo, hi) ->
              let a, b = world_bounds piece.id bounds in
              Some (lower lo a, upper hi b)) None cooked.cook.pieces)
    | framed, _ -> framed in
  let document_changed = doc != value.doc in
  { core = { value' with timeline; cook = cooked.cook; edit_error = cooked.edit_error;
      status_fps; status_fps_at; history; focus = result.focus;
      pane_keys = result.pane_keys; leader; prompt;
      queued = (match result.prompt_intent with Some (Run_action action) -> [action] | _ -> []);
      notice = if document_changed && Option.is_none loaded && not undone then None
        else notice };
    effects; prepared_changed = cooked.prepared_changed;
    scene_changed = doc.scene != value.doc.scene || cooked.prepared_changed;
    framed;
    loaded_view = Option.map (fun (preset : Preset.loaded) -> preset.view) loaded;
    actions; panel = result.panel;
    input = if not result.grab then frame
      else { frame with mouse_buttons = []; mouse_delta = 0., 0.;
        events = List.filter (function
          | Event.MouseMoved _ | MousePressed _ | MouseReleased _
          | MouseScrolled _ -> false
          | _ -> true) frame.events } }

(* Environment-owned scene edits (camera bookkeeping, follow viewport).
   [`Reset] starts the history, [`Amend] folds into the present entry, and
   [`View time] coalesces a burst of view edits (a drag, a wheel gesture)
   into one undo entry. *)
let scene_edit value mode ?(active_camera = value.doc.active_camera) scene =
  let doc = { value.doc with scene = { value.doc.scene with graph = scene };
    active_camera } in
  let history = match mode with
    | `Reset -> Editor_core.History.create doc
    | `Amend -> Editor_core.History.record ~merge:Repair doc value.history
    | `View time -> Editor_core.History.record
        ~merge:(Burst { key = "view"; at = time; window = 0.25 })
        doc value.history in
  { value with doc; history;
    graph_view = if value.level <> Document.Scene then value.graph_view
      else Pxui_graph.with_document scene value.graph_view
        |> Pxui_graph.with_flagged active_camera }

let machinery value ~all_ui_visible =
  if all_ui_visible || value.leader <> Leader.Idle then Pxui.Ui.scene value.ui
  else []

let close value =
  Pxui.Ui.destroy value.ui;
  Cook.close value.cook

(* A sketch-driven settings change: one undo step and a fresh cook, since
   [prepare] reads the settings. *)
let set_settings value settings =
  if settings == value.doc.settings then value else
  let doc = { value.doc with settings } in
  { value with doc; cook = Cook.force value.cook;
    history = Editor_core.History.record doc value.history }

(* The scene's World at timeline [time] (the day cycle advances with it). *)
let world value ~time = match Objects.ids "world" (scene value) with
  | id :: _ ->
      Option.bind (Edit_graph.find (scene value) ~node_id:id) (fun node ->
        Option.bind (Document.Layout.find_opt id value.doc.Document.networks)
          (fun network -> Layers.to_world ~time node network))
  | [] -> None

(* Visible objects' world transforms with their latest cook. *)
let placed_pieces ?(render = false) value =
  List.filter_map (fun (piece : _ Cook.piece) ->
    match Edit_graph.find (scene value) ~node_id:piece.id with
    | Some node when Objects.visible node && (not render || Objects.flag "render" node) ->
        Some (Objects.world (scene value) piece.id, piece)
    | Some _ | None -> None) (pieces value)

let world_id value = match Objects.ids "world" (scene value) with
  | id :: _ -> Some id | [] -> None

(* A parameter edit made in the view (a map drag, a World rotation): one
   undo entry per pointer gesture. *)
let edit_node value level node_id values ~label =
  match Document.network value.doc level with
  | None -> value
  | Some network ->
      match Edit_graph.apply_parameters network.graph ~node_id values with
      | Error _ -> value
      | Ok (graph, _) ->
          let doc = Document.with_network value.doc level { network with graph } in
          { value with doc;
            history = Editor_core.History.record ~label ~merge:(Gesture 1) doc value.history;
            graph_view = if level = value.level
              then Pxui_graph.with_document graph value.graph_view else value.graph_view }
