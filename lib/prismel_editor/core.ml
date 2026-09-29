open Prismel
open Procedural
open Common
open Editor_document

type bounds = Cook.bounds
module Level_map = Map.Make (struct
  type t = Document.level
  let compare = Stdlib.compare
end)

(* How the graph pane shows the open network. *)
type projection = Graph_view | List_view | Text_view

type text_cache = {
  level : Document.level;
  source : Flow_sop.Network.t;
  definitions : Document.definition Document.String_map.t;
  displayed : int option;
  qualified : bool;
  printed : (Flow_sop.Print.t, Flow.Diagnostic.t) result;
  lines : string array;
  max_columns : int;
  node_at_line : int option array;
}

type prompt =
  | Keys
  | Saving of string
  | Palette of string  (* command search query *)
  | Browsing of { query : string; presets : (string * float) list }

type prompt_intent = Save_preset_file of string | Load_preset_file of string
  | Delete_preset_file of { name : string; query : string }
  | Run_action of Leader.action

type timeline_intent = Pxui_shell.Timeline_bar.intent =
  Pause_toggle | Stop_playback | Reset_playback | Seek_playback of int64

type 'panel frame_result = {
  workspace : Pxui_shell.Layout.t;
  focus : Pxui_shell.Layout.column;
  pane_keys : (int * Pxui_shell.Layout.column) list;
  graph_view : Pxui_graph.t;
  tree : Pxui_shell.Tree.t;
  document : Flow_sop.Network.t;  (* the open network after this frame's edits *)
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
  graph_changes : Pxui_graph.change list;
  tree_intents : Pxui_shell.Tree.intent list;
  text_toggle : bool;
  open_graph : int option;
  settings_changes : (string * Parameter.value) list;
  hide_guide : bool;
  handle_changes : (int * (string * Parameter.value) list) option;
}

type 'prepared t = {
  code_graph : Graph.t;
  preferences : string;
  guide : bool;
  hud : (string * float) option;
  presets : string;  (* preset directory *)
  name : string;  (* sketch name recorded in presets *)
  prompt : prompt option;
  notice : string option;
  doc : Document.t;  (* always the history's present *)
  level : Document.level;
  scene_level : bool;  (* false: one geometry object, no scene to go up to *)
  projections : projection Level_map.t;
  qualified_text : bool Level_map.t;
  text_cache : text_cache option;
  map_view : bool;  (* in the World, the view pane shows the lat-long map *)
  live_cook : bool;  (* cook while a drag holds the pointer *)
  rows : (Flow_sop.Network.t * int * Editor_core.Network_layout.t
          * (Pxui_shell.Tree.row array * string list)) option;
  (* the list's rows, cached by network, display node, and tile layout *)
  factories : Edit_graph.factory list;  (* the SOP catalog *)
  graph_view : Pxui_graph.t;
  tree : Pxui_shell.Tree.t;
  ui : Pxui.Ui.t;
  workspace : Pxui_shell.Layout.t;
  timeline : Sketch_support.Timeline.t;
  cook : 'prepared Cook.t;
  edit_error : string option;
  status_fps : int option;
  status_fps_at : float;
  history : Document.t Editor_core.History.t;
  focus : Pxui_shell.Layout.column;
  pane_keys : (int * Pxui_shell.Layout.column) list;
  leader : Leader.state;
  held_keys : Input.key list;
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
  let x, y, width, height = bounds in
  Pxui.Ui.panel ui ~x:(float_of_int x) ~y:(float_of_int y)
    ~width:(float_of_int width) ~height:(float_of_int height)
    ~padding:0 "workspace-inspector-panel" build

let inspector_rows (network : Flow_sop.Network.t)
    (layout : Editor_core.Network_layout.t)
    (applied : Flow.Port_type.value Flow_sop.Port.Map.t) node_id fields
    value_parameters =
  let module Port = Flow_sop.Port in
  let module Pmap = Port.Map in
  let module Layout = Editor_core.Network_layout in
  let live = function
    | Flow.Port_type.Float_value value -> Printf.sprintf "%.5g" value
    | Int_value value -> string_of_int value
    | Bool_value value -> string_of_bool value
    | Vec3_value (x, y, z) -> Printf.sprintf "(%.3g, %.3g, %.3g)" x y z in
  let source target = match Pmap.find_opt target network.drives with
    | None -> None
    | Some (Flow_sop.Drive.Expr expression) ->
        Some ("=" ^ Flow.Expr.infix expression)
    | Some (Flow_sop.Drive.Wire {node; output}) ->
        let label = match Flow.Graph.find network.values ~node_id:node with
          | Some value -> value.label
          | None -> Option.fold ~none:("#" ^ string_of_int node) ~some:Node.label
              (Edit_graph.find network.geometry ~node_id:node) in
        let arrow = if Layout.Port_set.mem (target.node, target.path) layout.wireless
          then "⌁ " else "← " in
        Some (arrow ^ label ^ "." ^ output) in
  let applied target = Option.map live (Pmap.find_opt target applied) in
  let pins = Option.value ~default:Layout.String_map.empty
      (Layout.Int_map.find_opt node_id layout.rows) in
  let splits = Option.value ~default:Layout.String_set.empty
      (Layout.Int_map.find_opt node_id layout.split) in
  Result.map (List.map (fun (parameter : Port.parameter) ->
    let target = {Port.node = node_id; path = parameter.path} in
    let components = Port.components parameter |> List.filter_map (fun (part : Port.parameter) ->
      let port = {target with path = part.path} in
      Option.map (fun source -> part.path, source, applied port) (source port)) in
    let drive = source target in
    let locked = drive <> None || components <> [] in
    let active = match value_parameters, parameter.fields with
      | Some value, field :: _ -> Flow.Value_kind.field_active value ~name:field.name
      | _ -> true in
    let shown = Flow_sop.Exposure.shown ~active ~geometry:false ~driven:locked
        ~pin:(Layout.String_map.find_opt parameter.path pins)
        ~overridden:(Flow_sop.Exposure.overridden parameter)
        ~primary:(Flow_sop.Exposure.primary ~schema:fields parameter) () in
    let split = if parameter.ty = Some Flow.Port_type.Vec3 then
        Some (Layout.String_set.mem parameter.path splits || components <> [])
      else None in
    { Pxui_shell.Inspector.path = parameter.path; fields = parameter.fields;
      shown; locked; drive; live = applied target; components; split }))
    (Port.parameters fields)

(* ---- levels ---- *)

let scene value = Document.scene_graph value.doc

let kind value id = Option.map Node.operation (Edit_graph.find (scene value) ~node_id:id)

let level_key = function
  | Document.Scene -> "scene"
  | Inside id -> "object:" ^ string_of_int id
  | Compound {owner; path} ->
      "compound:" ^ string_of_int owner ^ ":"
      ^ String.concat ":" (List.map string_of_int path)

let catalog value = function
  | Document.Scene -> Objects.catalog @ [Layers.Settings.factory]
  | Compound _ -> value.factories
  | Inside id -> (match kind value id with
    | Some "geometry" -> value.factories
    | Some "world" -> Layers.catalog
    | Some _ | None -> [])

let network value = Option.get (Document.network value.doc value.level)
let document value = (network value).graph.geometry

let value_catalog =
  let entry kind key label category =
    let ports = Flow_sop.Port.parameters
        (Flow.Value_kind.fields (Flow.Value_kind.make kind))
      |> Result.value ~default:[]
      |> List.filter_map (fun (port : Flow_sop.Port.parameter) ->
        Option.map (fun ty -> port.path, ty) port.ty) in
    { Pxui_graph.key = "value/" ^ key; label; category; arity = 0; ports } in
  List.map (fun kind -> entry kind (Flow.Value_kind.key kind)
    (Flow.Value_kind.label kind) (Flow.Value_kind.category kind))
    (List.filter (( <> ) Flow.Value_kind.Math) Flow.Value_kind.all)
  @ List.map (fun (name, _) -> entry Flow.Value_kind.Math ("math/" ^ name)
      (String.capitalize_ascii name) ["Math"]) Flow.Expr.operators

let projection value =
  match Level_map.find_opt value.level value.projections with
  | Some projection -> projection
  | None -> (match value.level with
    | Document.Scene -> List_view
    | Compound _ -> Graph_view
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
  let gx, gy, gw, gh = (Pxui_shell.Layout.geometry value.workspace frame).graph in
  Pxui_graph.create_document ~x:gx ~y:gy ~width:(max 1 gw) ~height:(max 1 gh)
    ~definitions:(Document.flow_definitions value.doc)
    ~display_enabled:(match level with Compound _ -> false
      | Scene | Inside _ -> true)
    ~namespace:(match level with Document.Scene -> "scene"
      | Inside id when kind value id = Some "world" -> "world"
      | Inside _ -> "sop" | Compound _ -> "sop compound")
    ~catalog:(Pxui_graph.catalog_of_factories (catalog { value with level } level)
      @ if (network.context = Flow.Context.Sop) then value_catalog else [])
    ~flaggable:(fun info -> level = Document.Scene && info.Edit_graph.operation = "camera")
    ~enterable:(fun info -> level = Document.Scene && enterable value info.Edit_graph.id)
    network.graph
  |> Network_view.to_view network
  |> Pxui_graph.with_flagged (if level = Document.Scene then value.doc.active_camera else None)

let open_level value level frame =
  if level = value.level then value else
  let () = Pxui.Ui.unfocus value.ui in
  let world = match level with
    | Document.Inside id -> kind value id = Some "world"
    | Scene | Compound _ -> false in
  { value with level; graph_view = view_of value level frame
      |> Pxui_graph.carry_last_added ~from:value.graph_view; map_view = world;
    tree = Pxui_shell.Tree.create () }

(* The geometry objects to cook: visible ones, each with its network. *)
let geometry_objects value =
  List.filter_map (fun id ->
    match Edit_graph.find (scene value) ~node_id:id,
        Document.Layout.find_opt id value.doc.Document.networks with
    | Some node, Some network when Objects.visible node
        && not (Edit_graph.is_bypassed (scene value) ~node_id:id) ->
        Option.map (fun displayed -> id, network.Document.graph, displayed) network.displayed
    | _ -> None) (Objects.ids "geometry" (scene value))

(* The object the sketch-facing single-object accessors describe: the open
   one, else the first visible geometry object. *)
let focus_object value = match value.level with
  | Inside id when kind value id = Some "geometry" -> Some id
  | Compound {owner; _} -> Some owner
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
let panes value frame = Pxui_shell.Layout.geometry value.workspace frame
let column_visible value column = not (Pxui_shell.Layout.collapsed value.workspace column)

(* The transform the open network's handles live in: an object's own when
   inside it, the selected object's parent chain at the scene level. *)
let space value = match value.level with
  | Inside id when kind value id = Some "geometry" -> Objects.world (scene value) id
  | Compound {owner; _} -> Objects.world (scene value) owner
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
  | "time" | "value" | "math" | "combine_xyz" | "separate_xyz" | "remap" ->
      "V", hex "#70589a"
  | "gradient" | "sky" | "shape" | "scatter" | "room" -> "·", hex "#6d8a95"
  | _ -> "S", hex "#566463"

let scene_rows ?active document graph_view =
  let infos = Edit_graph.inspect document in
  let children = Hashtbl.create 16 in
  let y id = match Pxui_graph.node_position graph_view id with
    | Some (_, y) -> y | None -> 0. in
  List.iter (fun (info : Edit_graph.node_info) ->
    let parent = if Array.length info.inputs > 0 then info.inputs.(0) else None in
    Hashtbl.replace children parent
      (info :: Option.value ~default:[] (Hashtbl.find_opt children parent))) infos;
  let sorted parent = List.sort (fun (a : Edit_graph.node_info) b ->
      let order = Float.compare (y a.id) (y b.id) in
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

let trunk_rows (network : Flow_sop.Network.t) ~viewed ~flags =
  Array.map (fun (id, depth, link) ->
    let geometry = Edit_graph.find network.Flow_sop.Network.geometry ~node_id:id in
    let value = Flow.Graph.find network.values ~node_id:id in
    let label = match geometry, value with
      | Some node, _ -> Node.label node
      | None, Some node -> node.label
      | None, None -> "" in
    let operation = match geometry, value with
      | Some node, _ -> Node.operation node
      | None, Some node -> Flow.Value_kind.key (Flow.Value_kind.kind node.parameters)
      | None, None -> "" in
    let driven, set = match Flow_sop.Network.parameters network ~node_id:id with
      | Error _ -> 0, 0
      | Ok parameters -> List.fold_left (fun (driven, set) parameter ->
          let port path = Flow_sop.Port.{node = id; path} in
          let wired path = Flow_sop.Port.Map.mem (port path) network.drives in
          let component_paths = List.map (fun component ->
            component.Flow_sop.Port.path) (Flow_sop.Port.components parameter) in
          let is_driven = wired parameter.path || List.exists wired component_paths in
          let overridden = List.exists (fun (field : Parameter.field_view) ->
            let path = match field.vec3 with
              | Some (_, index) ->
                  parameter.path ^ "." ^ [|"x"; "y"; "z"|].(index)
              | None -> parameter.path in
            field.current <> field.default && not (wired parameter.path || wired path))
            parameter.fields in
          driven + Bool.to_int is_driven, set + Bool.to_int overridden)
          (0, 0) parameters in
    let details = [operation] @
      (if driven > 0 then [Printf.sprintf "%d driven" driven] else []) @
      (if set > 0 then [Printf.sprintf "%d set" set] else []) @
      (if viewed = id then ["VIEW"] else []) @
      (if Edit_graph.is_bypassed network.geometry ~node_id:id then ["M"] else []) in
    { Pxui_shell.Tree.id; depth; link; ghost = false;
      label; detail = String.concat " · " details;
      badge = badge operation; flags = flags id geometry })
    (Pxui_graph.trunk network)

let rows value (network : Flow_sop.Network.t) graph_view = match value.level with
  | Document.Scene -> scene_rows ?active:value.doc.active_camera network.Flow_sop.Network.geometry graph_view,
      ["vis"; "rnd"]
  | Compound _ -> trunk_rows network ~viewed:(-1) ~flags:(fun _ _ -> []), []
  | Inside id when kind value id = Some "geometry" ->
      trunk_rows network ~viewed:(Pxui_graph.viewed graph_view) ~flags:(fun node_id node ->
        match node with Some _ -> [node_id = Pxui_graph.viewed graph_view]
        | None -> []), ["disp"]
  | Inside _ ->
      trunk_rows network ~viewed:(-1) ~flags:(fun _ node ->
        match node with
        | Some node when Objects.has_flag "visible" node -> [Objects.flag "visible" node]
        | _ -> []),
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

let scene_reorder_pairs document (rows : Pxui_shell.Tree.row array) ids delta =
  let indices = Array.to_list rows |> List.filter_map (fun row ->
      if List.mem row.Pxui_shell.Tree.id ids then Some row.id else None) in
  let ordered = if delta < 0 then indices else List.rev indices in
  List.filter_map (fun id ->
      let index = Array.find_index (fun row -> row.Pxui_shell.Tree.id = id) rows
        |> Option.get in
      let parent = Objects.parent document id in
      let rec neighbour i =
        if i < 0 || i >= Array.length rows then None
        else if not (List.mem rows.(i).id ids)
          && Objects.parent document rows.(i).id = parent
        then Some (id, rows.(i).id)
        else neighbour (i + if delta < 0 then -1 else 1) in
      if delta = 0 then None else neighbour (index + if delta < 0 then -1 else 1)) ordered

(* Tree intents become document edits, selection, or an entry request. *)
let apply_tree value (overlay, graph_view, tree, opened, label, rows) intent =
  let document = overlay.Flow_sop.Network.geometry in
  let overlay = match intent with Pxui_shell.Tree.Delete ids ->
      Result.get_ok (Flow_sop.Network.remove_nodes ids overlay) | _ -> overlay in
  let with_document geometry view =
    Pxui_graph.with_document (Result.get_ok (Doc.update_geometry (fun _ -> Ok geometry) overlay)) view in
  let module T = Pxui_shell.Tree in
  let world = match value.level with
    | Document.Inside id -> kind value id = Some "world"
    | Scene | Compound _ -> false in
  let geometry = match value.level with
    | Document.Inside id -> kind value id = Some "geometry"
    | Scene | Compound _ -> false in
  let stack () = Array.to_list rows
    |> List.filter_map (fun (row : T.row) -> if row.link then None else Some row.id) in
  let restacked order =
    let document = restack document order in
    let top = List.nth order (List.length order - 1) in
    document, Pxui_graph.view top (with_document document graph_view),
    tree, opened, Some "Reorder layers", rows in
  let move_in order ids target drop =
    let rest = List.filter (fun id -> not (List.mem id ids)) order in
    List.concat_map (fun id ->
      if id <> target then [id]
      else match drop with
        | T.Before -> ids @ [id] | After | Inside -> id :: ids) rest in
  let document, graph_view, tree, opened, label, rows = match intent with
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
              let offset = if drop = Before then index - List.length ids else index + 1 in
              id, x, y +. 36. *. float_of_int offset) ids) graph_view
        | _ -> graph_view in
      document, with_document document graph_view, tree, opened,
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
           document, with_document document graph_view, tree, opened,
           Some "Reparent", rows)
  | Outdent ids when value.level = Document.Scene ->
      let document = List.fold_left (fun document id ->
          match Objects.parent document id with
          | Some parent -> reparent document [id] (Objects.parent document parent)
          | None -> document) document ids in
      document, with_document document graph_view, tree, opened,
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
      let graph_view = List.fold_left (fun view (id, neighbour) ->
          match Pxui_graph.node_position view id, Pxui_graph.node_position view neighbour with
          | Some (x, y), Some (nx, ny) ->
              Pxui_graph.place_nodes [id, x, ny; neighbour, nx, y] view
          | _ -> view) graph_view (scene_reorder_pairs document rows ids delta) in
      document, graph_view, tree, opened,
      Some "Reorder", rows
  | Rename (id, name) ->
      (match Option.map (Node.relabel name) (Edit_graph.find document ~node_id:id) with
       | Some node -> (match Edit_graph.replace_node node document with
         | Ok document -> document, with_document document graph_view,
             tree, opened, Some "Rename", rows
         | Error _ -> document, graph_view, tree, opened, label, rows)
       | None -> document, graph_view, tree, opened, label, rows)
  | Activate id when geometry ->
      document, Pxui_graph.view id graph_view, tree, opened, Some "Display", rows
  | Activate id -> document, graph_view, tree, Some id, label, rows
  | Delete ids ->
      let document = Edit_graph.remove_nodes ids document in
      document, Pxui_graph.clear_selection (with_document document graph_view),
      tree, opened, Some "Delete", rows
  | Move _ | Indent _ | Outdent _ | Reorder _ ->
      document, graph_view, tree, opened, label, rows

  in Result.get_ok (Doc.update_geometry (fun _ -> Ok document) overlay),
    graph_view, tree, opened, label, rows

(* ---- creation ---- *)

(* The document a sketch starts from: its code graph becomes the geometry
   object geo1 (camera SOPs in it move up to the scene as camera objects),
   plus [seed]'s additions to the scene. *)
let initial_doc ~settings ~seed_scene ?program code_graph =
  let sop = match program with
    | Some (program : Flow_sop.Program.t) -> program.network
    | None -> Flow_sop.Network.of_geometry (Edit_graph.of_graph code_graph) in
  let cameras = List.filter_map (fun (info : Edit_graph.node_info) ->
      if info.operation = "camera" then Some info.node else None)
      (Edit_graph.inspect sop.geometry) in
  let sop = Result.get_ok (Flow_sop.Network.remove_nodes
      (List.map Node.id cameras) sop) in
  let geometry = Result.get_ok (Edit_graph.instantiate_optional
      Objects.Geometry.factory [None]) |> Node.relabel "geo1" in
  let empty_scene = Result.get_ok (Edit_graph.add_node ~factory:Objects.Geometry.factory
      ~inputs:[|None|] geometry Edit_graph.empty) in
  let scene = List.fold_left (fun scene camera ->
      Result.value ~default:scene (Edit_graph.add_node camera scene))
      empty_scene cameras in
  let scene = seed_scene scene in
  let displayed = match program with
    | Some program when Option.fold ~none:false ~some:(fun id ->
        Edit_graph.find sop.geometry ~node_id:id <> None) program.display ->
        program.display
    | Some _ -> None
    | None -> Edit_graph.root sop.geometry in
  let definitions = match program with
    | None -> Document.String_map.empty
    | Some program -> Flow_sop.Network.String_map.fold (fun name spec definitions ->
        let displayed = Edit_graph.inspect spec.Flow_sop.Network.body.geometry
          |> List.find_opt (fun (info : Edit_graph.node_info) ->
            info.operation = "flow_outputs")
          |> Option.map (fun (info : Edit_graph.node_info) -> info.id) in
        Document.String_map.add name Document.{spec;
          layout = Editor_core.Network_layout.empty; displayed} definitions)
        program.definitions Document.String_map.empty in
  { Document.scene = Document.of_geometry ~context:Flow.Context.Scene scene (Some (Node.id geometry));
    networks = Document.Layout.singleton (Node.id geometry)
      Document.{context = Flow.Context.Sop; graph = sop;
        layout = Editor_core.Network_layout.empty; displayed};
    definitions;
    compiled_ids = Flow_sop.Instance_path.Map.empty;
    active_camera = None; settings },
  Node.id geometry

(* A World object for [world], with its layer network. *)
let add_world (doc : Document.t) world =
  let _, values = Layers.of_world world in
  let ( let* ) = Result.bind in
  let* node = Edit_graph.instantiate Layers.Settings.factory [] in
  let* graph = Edit_graph.add_node ~factory:Layers.Settings.factory node doc.scene.graph.geometry in
  let* graph, _ = Edit_graph.apply_parameters graph ~node_id:(Node.id node) values in
  let* network = Layers.network_of_world world in
  Ok { doc with scene = { doc.scene with graph = Result.get_ok (Flow_sop.Network.with_geometry graph doc.scene.graph) };
       networks = Document.Layout.add (Node.id node) network doc.networks }

(* A new World starts as a daylight sky with a sun, ready to turn. *)
let daylight = Option.value ~default:World.default (List.assoc_opt "daylight" World.presets)

let preferences_file () = match Sys.getenv_opt "PRISMEL_EDITOR_PREFERENCES" with
  | Some path when path <> "" -> path
  | Some _ | None -> Filename.concat (Filename.concat
      (Option.value ~default:"." (Sys.getenv_opt "HOME")) ".prismel") "preferences.json"

let read_preferences filename =
  Editor_core.Store.Settings.load ~sketch:"prismel-editor" filename

let save_guide filename guide =
  let ( let* ) = Result.bind in
  let* values = if Sys.file_exists filename then read_preferences filename else Ok [] in
  Editor_core.Store.Settings.save ~sketch:"prismel-editor" filename
    (("guide", Editor_core.Store.Settings.Bool guide) :: List.remove_assoc "guide" values)

let create ?(settings = Settings.none) ?(keymap = Leader.keymap)
    ?(seed_scene = fun _ scene -> scene) ?(scene_level = true) ?world
    ?(name = "sketch") ?presets ?(timeline_frames = 240)
    ?(layout = Pxui_shell.Layout.default) ?(factories = [])
    ?(seed = 0L) ?(grain = 16_384)
    ?domains ?(max_entries = 32)
    ?(max_payload_bytes = 256 * 1024 * 1024)
    ?program ~graph ~prepare () =
  let doc, geometry = initial_doc ~settings ?program
      ~seed_scene:(seed_scene factories) graph in
  let doc = match Option.map (add_world doc) world with
    | Some (Ok doc) -> doc | Some (Error _) | None -> doc in
  Result.bind (Result.map_error Flow.Diagnostic.to_string
    (Document.allocate_compiled_ids doc)) (fun doc ->
  Result.map (fun cook ->
      let workspace = Pxui_shell.Layout.create layout in
      let presets = match presets with
        | Some directory -> directory
        | None -> Filename.concat (Filename.concat
            (Option.value ~default:"." (Sys.getenv_opt "HOME")) ".prismel")
            (Preset.sanitize name) in
      let level = if scene_level then Document.Scene else Inside geometry in
      let preferences = preferences_file () in
      let guide = match read_preferences preferences with
        | Ok values -> Option.value ~default:true (Editor_core.Store.Settings.bool values "guide")
        | Error _ -> true in
      let value = { preferences; guide; hud = None; code_graph = graph; presets; name; prompt = None; notice = None;
        doc; level; scene_level; projections = Level_map.empty;
        qualified_text = Level_map.empty; text_cache = None; map_view = false;
        rows = None; live_cook = true;
        factories;
        graph_view = Pxui_graph.create (Sop.points [||]);
        tree = Pxui_shell.Tree.create (); held_keys = [];
        ui = Pxui.Ui.create (); workspace;
        timeline = Sketch_support.Timeline.create (); cook;
        edit_error = None; status_fps = None;
        status_fps_at = Float.neg_infinity;
        history = Editor_core.History.create doc;
        focus = Pxui_shell.Layout.View; pane_keys = []; leader = Leader.Idle;
        keymap; timeline_frames = max 1 timeline_frames; queued = [] } in
      (* Record the laid-out positions of every network as the first state. *)
      let doc = List.fold_left (fun doc level ->
          let view = view_of { value with doc } level initial_frame in
          let network = Option.get (Document.network doc level) in
          Document.with_network doc level
            (Network_view.of_view network view))
          doc (Document.Scene :: List.map (fun (id, _) -> Document.Inside id)
            (Document.Layout.bindings doc.networks)) in
      { value with doc; history = Editor_core.History.create doc;
        graph_view = view_of { value with doc } level initial_frame })
    (Cook.create ~prepare ~seed ~grain ?domains ~max_entries
      ~max_payload_bytes ()))

let truncate limit text = if String.length text <= limit then text
  else if limit <= 3 then String.make (max 0 limit) '.'
  else String.sub text 0 (limit - 3) ^ "..."

let level_name value = match value.level with
  | Document.Scene -> "scene"
  | Inside id -> "scene › " ^ Option.fold ~none:"?" ~some:Node.label
      (Edit_graph.find (scene value) ~node_id:id)
  | Compound {owner; _} as level ->
      let root = Option.fold ~none:"?" ~some:Node.label
        (Edit_graph.find (scene value) ~node_id:owner) in
      "scene › " ^ root ^ " › "
      ^ String.concat " › " (List.map (fun name ->
        String.capitalize_ascii (String.map (function '_' -> ' ' | c -> c) name)
        ^ " · sop compound") (Document.compound_names value.doc level))

let printed_level value =
  let saved = network value in
  let qualified = Option.value ~default:false
      (Level_map.find_opt value.level value.qualified_text) in
  match value.text_cache with
  | Some cache when cache.level = value.level && cache.source == saved.graph
      && cache.definitions == value.doc.definitions
      && cache.displayed = saved.displayed && cache.qualified = qualified -> cache
  | _ ->
      let printed = match saved.context with
        | Flow.Context.Scene | World | Value ->
            Error (Flow.Diagnostic.error ~code:"E_CONTEXT_RESERVED"
              "Flow text is available for SOP networks and compounds")
        | Sop ->
            let definitions = Document.flow_definitions value.doc in
            Result.bind (Flow_sop.Catalog.of_factories ~version:1 value.factories)
              (fun catalog -> match value.level with
                | Compound _ ->
                    (match List.rev (Document.compound_names value.doc value.level) with
                     | name :: _ -> Flow_sop.Print.definition ~qualified ~precision:6 ~catalog
                         ~definitions name
                     | [] -> Error (Flow.Diagnostic.error ~code:"E_UNBOUND"
                         "Open compound has no definition"))
                | Scene | Inside _ ->
                    Flow_sop.Print.network ~qualified ~precision:6 ~name:value.name ~context:saved.context
                      ~catalog ~display:saved.displayed ~definitions saved.graph) in
      let lines = Array.of_list (String.split_on_char '\n'
        (match printed with Ok print -> print.text
          | Error diagnostic -> diagnostic.message)) in
      let node_at_line = Array.make (Array.length lines) None in
      (match printed with
       | Ok print -> List.iter (fun (id, line) ->
           if line > 0 && line <= Array.length node_at_line then
             node_at_line.(line - 1) <- Some id) print.binding_lines
       | Error _ -> ());
      {level = value.level; source = saved.graph;
       definitions = value.doc.definitions; displayed = saved.displayed;
       qualified; printed; lines;
       max_columns = Array.fold_left (fun longest line ->
         max longest (String.length line)) 0 lines;
       node_at_line}

let move_text_selection cache selected direction =
  let bindings = match cache.printed with
    | Ok print -> print.binding_lines | Error _ -> [] in
  let ids = List.map fst bindings in
  match ids with
  | [] -> None
  | _ ->
      let index = match selected with
        | None -> if direction = Pxui_graph.Up then List.length ids - 1 else 0
        | Some id ->
            (match List.find_index (( = ) id) ids with
             | None -> if direction = Pxui_graph.Up then List.length ids - 1 else 0
             | Some index -> max 0 (min (List.length ids - 1)
                 (index + if direction = Pxui_graph.Up then -1 else 1))) in
      List.nth_opt ids index

let text_pane ui ~bounds:(x, y, width, height) ~title ~reveal cache ~selected =
  let module Ui = Pxui.Ui in
  let row = float_of_int (Ui.row_height ui) in
  let x = float_of_int x and y = float_of_int y
  and width = float_of_int width and height = float_of_int height in
  let theme = Ui.theme ui in
  let header = Ui.box ui ~flags:Ui.(clickable + blocking)
      ~w:(Ui.Px width) ~h:(Ui.Px row) ~at:(x, y) "flow-text-header" in
  let toggle = (Ui.signal ui header).clicked && Result.is_ok cache.printed in
  Ui.draw ui header (fun paint _ ->
    Ui.Paint.fill paint ~x ~y ~w:width ~h:row theme.foreground;
    Ui.Paint.text paint ~at:(x +. 8., y +. 5.) ~color:theme.input
      (title ^ (match cache.printed with Error _ -> "  ·  text"
        | Ok _ -> "  ·  qualified names: " ^
            (if cache.qualified then "on" else "off"))));
  let body_y = y +. row and body_h = Float.max 0. (height -. row) in
  let body = Ui.box ui ~flags:Ui.(clickable + scroll + clip + blocking)
      ~w:(Ui.Px width) ~h:(Ui.Px body_h) ~at:(x, body_y)
      ~scroll_step:row "flow-text-body-v2" in
  let signal = Ui.signal ui body in
  let maximum = Float.max 0. (float (Array.length cache.lines) *. row -. body_h) in
  let vertical = Float.max 0. (Float.min maximum (Ui.scroll_offset ui body)) in
  let vertical = if not reveal then vertical else
    match cache.printed, selected with
    | Ok print, Some id ->
        (match List.assoc_opt id print.binding_lines with
         | Some line when float (line - 1) *. row < vertical ->
             float (line - 1) *. row
         | Some line when float line *. row > vertical +. body_h ->
             Float.min maximum (float line *. row -. body_h)
         | _ -> vertical)
    | _ -> vertical in
  if reveal then Ui.set_scroll_offset ui body vertical;
  let content = Ui.within ui body (fun () ->
    Ui.box ui ~w:(Ui.Px width)
      ~h:(Ui.Px (Float.max body_h (float (Array.length cache.lines) *. row)))
      "flow-text-content") in
  let max_horizontal = Float.max 0. (float cache.max_columns *. 7. -. width +. 16.) in
  let horizontal = Float.max 0. (Float.min max_horizontal
    (float (Ui.state ui content ~default:0) /. 1000.
      +. fst signal.scroll *. row)) in
  Ui.set_state ui content (int_of_float (Float.round (horizontal *. 1000.)));
  let picked = if not signal.pressed || signal.button <> Some Input.LeftButton
    then None else
    let _, py = signal.press_point in
    let line = int_of_float (Float.floor ((py -. body_y +. vertical) /. row)) in
    if line < 0 || line >= Array.length cache.node_at_line then None
    else cache.node_at_line.(line) in
  Ui.draw ui body (fun paint _ ->
    Ui.Paint.fill paint ~x ~y:body_y ~w:width ~h:body_h theme.panel);
  Ui.draw ui content (fun paint (_, content_y, _, _) ->
    let offset = body_y -. content_y in
    let first = max 0 (int_of_float (Float.floor (offset /. row))) in
    let last = min (Array.length cache.lines - 1)
        (int_of_float (Float.ceil ((offset +. body_h) /. row))) in
    for index = first to last do
      let line_y = content_y +. float_of_int index *. row in
      if cache.node_at_line.(index) = selected then
        (match selected with Some _ ->
          Ui.Paint.fill paint ~x ~y:line_y ~w:width ~h:row
            (Pxui.Theme.pressed_fill theme) | None -> ());
      Ui.Paint.text paint ~at:(x +. 8. -. horizontal, line_y +. 5.)
        ~color:theme.foreground cache.lines.(index)
    done);
  picked, toggle

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
        "u up · drag map: move layer/sun · t dome/light · n reseed · d day cycle · [ ] time · Space l 3D/map"
    | Compound _ -> "u up · Space a add · Space l list/graph"
    | Inside _ when value.scene_level -> "u up · Space a add · Space l list/graph"
    | Inside _ -> "Space a add · Space l list/graph" in
  cook ^ " · " ^ level_name value ^ (if hint = "" then "" else " · " ^ hint)

(* The status strip under the view: kit text on a dark bar. *)
let status_box value ui (frame : Frame.t) ~render_status ~context ~commands =
  let x, y, width, height = (Pxui_shell.Layout.geometry value.workspace frame).status in
  if height <= 0 then false
  else if value.guide && value.focus = Pxui_shell.Layout.Graph then
    Pxui_shell.Status_bar.guide ui ~bounds:(x, y, width, height) ~context commands
  else begin
    let text = truncate (max 1 ((width - 80) / 7))
        (status_text value ^ match render_status with
          | None -> "" | Some status -> " · " ^ status) in
    Pxui_shell.Status_bar.draw ui ~bounds:(x, y, width, height)
      ~text ~fps:value.status_fps;
    false
  end

(* Leader actions owned by the workspace; the environment handles the rest
   from [update.actions]. *)
let apply_action value (frame : Frame.t) (workspace, graph_view, tree, timeline, changes) action =
  let module T = Sketch_support.Timeline in
  let timeline_step step = let timeline, more = step timeline in
    workspace, graph_view, tree, timeline, changes @ more in
  let pointer () =
    let gx, gy, gw, gh = (Pxui_shell.Layout.geometry workspace frame).graph in
    let mx, my = frame.mouse in
    if mx >= float gx && my >= float gy && mx < float (gx + gw) && my < float (gy + gh)
    then int_of_float mx, int_of_float my
    else gx + (gw / 3), gy + (gh / 3) in
  match action with
  | Leader.Toggle_timeline ->
      Pxui_shell.Layout.toggle Pxui_shell.Layout.Timeline workspace, graph_view, tree, timeline, changes
  | Toggle_graph ->
      Pxui_shell.Layout.toggle Pxui_shell.Layout.Graph workspace, graph_view, tree, timeline, changes
  | Toggle_inspector ->
      Pxui_shell.Layout.toggle Pxui_shell.Layout.Inspector workspace, graph_view, tree, timeline, changes
  | Open_camera ->
      Pxui_shell.Layout.expand Pxui_shell.Layout.Inspector workspace,
      Pxui_graph.clear_selection graph_view, tree, timeline, changes
  | Play_pause -> timeline_step T.toggle_pause
  | Reset -> timeline_step T.reset
  | Stop -> timeline_step T.stop
  | Add_node ->
      Pxui_shell.Layout.expand Pxui_shell.Layout.Graph workspace,
      Pxui_graph.open_menu_at (pointer ()) graph_view, tree, timeline, changes
  | Layout -> workspace, Pxui_graph.optimize_layout graph_view, tree, timeline, changes
  | Frame_tile when projection value = List_view ->
      workspace, graph_view, Pxui_shell.Tree.reveal tree, timeline, changes
  | Frame_tile -> workspace, Pxui_graph.frame_viewed graph_view, tree, timeline, changes
  | World_play when Sketch_support.Timeline.mode timeline <> Sketch_support.Timeline.Playing ->
      timeline_step T.toggle_pause
  | Hide_ui | Look_through | Fly | Save_preset | Browse_presets
  | Graph_command _ | List_command _ | Frame_camera | Undo | Redo | Command_palette
  | Guide_toggle | Guide_keys
  | Sketch_command _ | Toggle_projection | Enter | Up | Go_world | Group | Ungroup
  | Make_unique | Tool _
  | World_emit | World_reseed | World_time _ | World_play | World_preset _ ->
      workspace, graph_view, tree, timeline, changes

(* The undo label a graph intent gives its document change. *)
let intent_label = function
  | Pxui_graph.Connect_requested _ | Value_connect_requested _ -> Some "Connect"
  | Value_bind_requested _ | Wireless_changed _ -> Some "Bind"
  | Row_reset_requested {path; _} -> Some ("Reset " ^ path)
  | Expression_requested {target; _} -> Some ("Expression on " ^ target.path)
  | Fold_requested {path; _} -> Some ("Fold " ^ path)
  | Unfold_requested {path; _} -> Some ("Unfold " ^ path)
  | Disconnect_requested _ | Value_disconnect_requested _ -> Some "Disconnect"
  | Delete_nodes_requested _ -> Some "Delete"
  | Dissolve_nodes_requested _ -> Some "Dissolve"
  | Make_unique_requested _ -> Some "Make unique"
  | Bypass_requested _ -> Some "Bypass"
  | Add_requested _ -> Some "Add node"
  | Insert_requested _ -> Some "Insert node"
  | Paste_requested _ -> Some "Paste"
  | Viewed _ -> Some "Display"
  | Flag_requested _ -> Some "Set active camera"
  | Node_moved _ | Nodes_moved _ -> Some "Move"
  | Bend_changed _ -> Some "Bend wire"
  | Level_changed _ -> Some "Detail level"
  | Set_parameter_requested { path; _ } -> Some ("Set " ^ path)
  | Rename_requested _ -> Some "Rename node"
  | Rename_interface_requested _ -> Some "Rename interface port"
  | Reorder_interface_requested _ -> Some "Reorder interface"
  | Unexport_requested _ -> Some "Unexport interface port"
  | Export_requested target -> Some ("Export " ^ target.path)
  | Split_requested {group; _} -> Some ("Split " ^ group)
  | Row_pinned {path; _} -> Some ("Pin " ^ path)
  | Cut_wires_requested _ -> Some "Cut wires"
  | Selected _ | View_changed | Connection_selected _ | Frame_camera_requested _
  | Open_requested _ | Notice _ -> None

let in_world value = match value.level with
  | Document.Inside id -> kind value id = Some "world"
  | Scene | Compound _ -> false

(* World keys: edit the selected layer, or the World node in the scene. *)
let world_keys value (doc : Document.t) graph_view actions =
  let world_id = match value.level with Inside id -> Some id
    | Scene | Compound _ -> None in
  let edit_layer f label (doc, _) = match world_id, Pxui_graph.selected graph_view with
    | Some id, Some layer ->
        (match Document.network doc (Inside id) with
         | Some network ->
             (match Option.bind (Edit_graph.find network.graph.geometry ~node_id:layer) f with
              | Some values ->
                  (match Edit_graph.apply_parameters network.graph.geometry ~node_id:layer values with
                   | Ok (graph, _) ->
                       Document.with_network doc (Inside id) { network with graph = Result.get_ok (Flow_sop.Network.with_geometry graph network.graph) }, Some label
                   | Error _ -> doc, None)
              | None -> doc, None)
         | None -> doc, None)
    | _ -> doc, None in
  let edit_world f label (doc, _) = match world_id with
    | Some id ->
        (match Option.bind (Edit_graph.find doc.Document.scene.graph.geometry ~node_id:id) f with
         | Some values ->
             (match Edit_graph.apply_parameters doc.scene.graph.geometry ~node_id:id values with
              | Ok (graph, _) -> { doc with scene = { doc.scene with graph = Result.get_ok (Flow_sop.Network.with_geometry graph doc.scene.graph) } }, Some label
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
                  doc.scene.graph.geometry ~node_id:id (snd (Layers.of_world world)) with
              | Ok network, Ok (graph, _) ->
                  { (Document.with_network doc (Inside id) network) with
                    scene = { doc.scene with graph = Result.get_ok (Flow_sop.Network.with_geometry graph doc.scene.graph) } }, Some ("Preset " ^ name)
              | _ -> state)
         | _ -> state)
    | _ -> state) (doc, None) actions

(* Commands that only mean something on this level and projection. *)
let routed value =
  let graph_shown = not (Pxui_shell.Layout.collapsed value.workspace Pxui_shell.Layout.Graph) in
  let listing = projection value = List_view in
  let texting = projection value = Text_view in
  if Pxui_graph.hinting value.graph_view && not (listing || texting) then
    List.filter (fun (command : Leader.command) -> match command.action with
      | Guide_toggle | Guide_keys -> true | _ -> false) value.keymap @ List.map (fun (command : _ Editor_core.Command.t) ->
      { command with scope = Some Pxui_shell.Layout.Graph;
        action = Leader.Graph_command command.action }) Pxui_graph.hint_bindings
  else List.filter (fun (command : Leader.command) -> match command.action with
    | List_command Pxui_shell.Tree.Activate_row -> (listing || texting) && graph_shown
    | List_command _ -> listing && graph_shown
    | Graph_command (Pxui_graph.Walk (Pxui_graph.Up | Pxui_graph.Down))
      when listing || texting -> graph_shown && (match command.trigger with
        | Some (Editor_core.Keymap.Chord (Input.KeyChar ('j' | 'k'), [])) -> true
        | _ -> false)
    | Graph_command Pxui_graph.Frame_all -> not (listing || texting) && graph_shown
    | Graph_command (Walk _ | Add | Connect_hint | Bind_hint | Show_wireless
      | Frame_selection) -> not (listing || texting) && graph_shown
    | Graph_command _ -> not texting && graph_shown
    | Frame_tile -> not texting && graph_shown
        && (listing || command.trigger = Some (Editor_core.Keymap.Leader "f"))
    | Frame_camera -> graph_shown
    | Add_node | Layout -> not texting && graph_shown
    | Group | Ungroup | Make_unique -> not texting && graph_shown && (match value.level with
        | Document.Inside id -> kind value id = Some "geometry"
        | Compound _ -> true | Scene -> false)
    | Enter -> value.scene_level || (match value.level with
        | Compound _ -> true
        | Inside id -> kind value id = Some "geometry"
        | Scene -> false)
    | Up -> value.scene_level || (match value.level with
        | Compound _ -> true | Scene | Inside _ -> false)
    | Go_world -> value.scene_level
    | World_emit | World_reseed | World_time _ | World_play | World_preset _ ->
        in_world value
    | _ -> true) value.keymap

(* A geometry object added in the scene gets a network with one box, a
   World its default layers. *)
let seed_networks value doc added =
  List.fold_left (fun doc id ->
    if Document.Layout.mem id doc.Document.networks then doc
    else match Option.map Node.operation (Edit_graph.find doc.Document.scene.graph.geometry ~node_id:id) with
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
                   (Document.of_geometry ~context:Flow.Context.Sop graph (Some (Node.id node))) doc.networks }
           | Some (Error _) | None -> doc)
      | Some "world" ->
          (match Layers.network_of_world daylight with
           | Ok network -> { doc with networks = Document.Layout.add id network doc.networks }
           | Error _ -> doc)
      | Some _ | None -> doc) doc added

(* Every editor path records the same immutable document. No-op/rejected
   edits leave both the present and the merge state untouched. *)
let commit ?(label = "Edit") ?(merge = Editor_core.History.Step) doc history =
  if doc == Editor_core.History.present history then history
  else Editor_core.History.record ~label ~merge doc history

let parameter_gesture operation level id values =
  operation ^ "/" ^ level_key level ^ "/" ^ string_of_int id ^ "/"
  ^ String.concat "/" (List.sort_uniq String.compare (List.map fst values))

let update value ~all_ui_visible ~text_focus ~camera_panel ~view_handles
    ~render_status ~view_state (frame : Frame.t) =
  let text_focus = text_focus || value.prompt <> None || Pxui_graph.editing value.graph_view
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
  let held_keys = frame.keys in
  let leader, commands, frame = Editor_core.Router.step ~previous_keys:value.held_keys
      keymap ~focus ~text_focus ~frame value.leader in
  let hud = match List.rev commands with
    | command :: _ -> Some (Editor_core.Keymap.label (Option.get command.trigger)
        ^ " · " ^ command.label, frame.time +. 1.5)
    | [] -> (match leader with
        | Leader.Pending prefix when leader <> value.leader ->
            Some ((if prefix = "" then "Space" else "Space " ^ prefix) ^ " · leader", frame.time +. 1.5)
        | _ -> value.hud) in
  let actions = List.map (fun (command : Leader.command) -> command.action) commands in
  let hud = match hud with Some (_, until) when frame.time >= until -> None | _ -> hud in
  let guide = List.fold_left (fun guide -> function Leader.Guide_toggle -> not guide
    | _ -> guide) value.guide actions in
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
  let applied = match value.level with
    | Document.Inside id -> Option.map (fun resolved -> resolved.Flow_sop.Value_lane.applied)
        (Cook.applied value.cook id)
    | Scene | Compound _ -> None in
  let graph_view = Pxui_graph.with_applied
      (Option.value ~default:Flow_sop.Port.Map.empty applied) value.graph_view in
  let value = {value with graph_view} in
  let workspace, graph_view, tree, timeline, timeline_changes = List.fold_left
      (apply_action value frame)
      (value.workspace, value.graph_view, value.tree, timeline, timeline_changes) actions in
  let graph_shown = all_ui_visible && not (Pxui_shell.Layout.collapsed workspace Pxui_shell.Layout.Graph) in
  let listing = projection value = List_view in
  let texting = projection value = Text_view in
  let text_cache = if texting && graph_shown then Some (printed_level value)
    else value.text_cache in
  let graph_view, command_changes = List.fold_left (fun (graph_view, changes) ->
    function
    | Leader.Graph_command (Walk (Pxui_graph.Up | Pxui_graph.Down))
      when graph_shown && listing -> graph_view, changes
    | Leader.Graph_command (Walk direction) when graph_shown && texting ->
        let selected = Option.bind text_cache (fun cache ->
          move_text_selection cache (Pxui_graph.selected graph_view) direction) in
        (match selected with Some id -> Pxui_graph.select id graph_view
          | None -> graph_view), changes
    | Leader.Graph_command command when graph_shown ->
        let mx, my = frame.mouse in
        let graph_view, emitted = Pxui_graph.run_command ~at:(int_of_float mx, int_of_float my)
            graph_view command in
        graph_view, changes @ emitted
    | _ -> graph_view, changes) (graph_view, []) actions in
  let document = document value in
  let open_network = (network value).graph in
  let rows_cache = match value.rows with
    | Some (source, viewed, layout, rows) when listing && source == open_network
        && viewed = Pxui_graph.viewed graph_view && layout == (network value).layout ->
        Some (source, viewed, layout, rows)
    | _ when listing -> Some (open_network, Pxui_graph.viewed graph_view, (network value).layout,
        rows value open_network graph_view)
    | _ -> None in
  let rows, columns = match rows_cache with
    | Some (_, _, _, rows) -> rows | None -> [||], [] in
  let selected () = Pxui_graph.selected_nodes graph_view
    |> List.sort (fun a b -> if Some a = Pxui_graph.selected graph_view then -1
      else if Some b = Pxui_graph.selected graph_view then 1 else Int.compare a b) in
  let tree, list_intents = List.fold_left (fun (tree, intents) -> function
    | Leader.Graph_command (Walk direction) when listing && graph_shown ->
        let command = if direction = Pxui_graph.Up then Pxui_shell.Tree.Up
          else Pxui_shell.Tree.Down in
        let tree, emitted = Pxui_shell.Tree.run_command tree rows
            ~selected:(selected ()) command in
        tree, intents @ emitted
    | Leader.List_command Pxui_shell.Tree.Activate_row -> tree, intents
    | Leader.List_command command when graph_shown ->
        let tree, emitted = Pxui_shell.Tree.run_command tree rows
            ~selected:(selected ()) command in
        tree, intents @ emitted
    | _ -> tree, intents) (tree, []) actions in
  let open_graph = if not graph_shown then None else
    List.find_map (function
      | Leader.List_command Pxui_shell.Tree.Activate_row when listing ->
          (match Pxui_shell.Tree.focused tree with
           | Some id -> Some id | None -> Pxui_graph.selected graph_view)
      | Leader.List_command Pxui_shell.Tree.Activate_row when texting ->
          Pxui_graph.selected graph_view
      | _ -> None) actions in
  let initial_frame_request = if List.mem Leader.Frame_camera actions
    then Some (Pxui_graph.viewed graph_view) else None in
  let build ui =
    let workspace = Pxui_shell.Chrome.update workspace ui shortcut_frame in
    let panes = Pxui_shell.Layout.geometry workspace frame in
    let root column bounds =
      column, Pxui_shell.Chrome.pane_root ui frame ~bounds
        ("workspace-pane-" ^ Leader.pane_name column) in
    let vx, vy, vw, _ = panes.view in
    let _, sy, _, sh = panes.status in
    let view, view_root = root Pxui_shell.Layout.View (vx, vy, vw, sy + sh - vy) in
    let graph, graph_root = root Pxui_shell.Layout.Graph panes.graph in
    let inspector_column, inspector_root =
      root Pxui_shell.Layout.Inspector panes.inspector in
    let timeline_column, timeline_root =
      root Pxui_shell.Layout.Timeline panes.timeline in
    let gx, gy, gw, gh = panes.graph in
    let graph_view = graph_view
      |> Pxui_graph.with_guide guide
      |> Pxui_graph.with_bounds ~x:gx ~y:gy ~width:(max 1 gw) ~height:(max 1 gh)
      |> Pxui_graph.with_visible
           (projection value = Graph_view
            && not (Pxui_shell.Layout.collapsed workspace Pxui_shell.Layout.Graph)) in
    let graph_view, graph_changes =
      if not (Pxui_shell.Layout.collapsed workspace Pxui_shell.Layout.Graph)
      then Pxui.Ui.within ui graph_root (fun () ->
        Pxui_graph.update graph_view ui shortcut_frame)
      else graph_view, [] in
    let tree, list_intents =
      if projection value = List_view
          && not (Pxui_shell.Layout.collapsed workspace Pxui_shell.Layout.Graph) then
        let tree, emitted = Pxui.Ui.within ui graph_root (fun () ->
          Pxui_shell.Tree.update tree ui shortcut_frame ~bounds:panes.graph
            ~title:(level_name value) ~columns rows
            ~selected:(selected ())) in
        tree, list_intents @ emitted
      else tree, list_intents in
    let text_selected, text_toggle = match text_cache with
      | Some cache when texting && not (Pxui_shell.Layout.collapsed workspace Pxui_shell.Layout.Graph) ->
          Pxui.Ui.within ui graph_root (fun () ->
            text_pane ui ~bounds:panes.graph ~title:(level_name value) cache
              ~reveal:(List.exists (function
                | Leader.Graph_command (Walk (Pxui_graph.Up | Pxui_graph.Down)) -> true
                | _ -> false) actions)
              ~selected:(Pxui_graph.selected graph_view))
      | _ -> None, false in
    let graph_changes = command_changes @ graph_changes in
    let frame_request = List.fold_left (fun request -> function
      | Pxui_graph.Frame_camera_requested id -> Some id
      | _ -> request) initial_frame_request graph_changes in
    let opened = List.fold_left (fun opened -> function
      | Pxui_graph.Open_requested id -> Some id
      | _ -> opened) None graph_changes in
    (* Selection is view state; inspection intents retain the selected stable
       id. Topology and parameter application wait until Ui.frame finishes. *)
    let graph_view = List.fold_left (fun view -> function
      | Pxui_shell.Tree.Select [] -> Pxui_graph.clear_selection view
      | Select ids -> Pxui_graph.select_nodes ids view
      | _ -> view) graph_view list_intents in
    let graph_view = match text_selected with
      | Some id -> Pxui_graph.select id graph_view | None -> graph_view in
    let inspector_visible = not (Pxui_shell.Layout.collapsed workspace Pxui_shell.Layout.Inspector) in
    let selected_ids = Pxui_graph.selected_nodes graph_view in
    let selected_id = match selected_ids with
      | [_] -> Pxui_graph.selected graph_view | _ -> None in
    let selected = Option.bind selected_id
        (fun node_id -> Edit_graph.find document ~node_id) in
    let unchanged = value.doc.settings in
    let open_network = network value in
    let panel, inspector_changes, settings_changes, live_cook =
      Pxui.Ui.within ui inspector_root (fun () -> match selected_ids with
      | _ when not inspector_visible ->
          None, [], [], value.live_cook
      | [] ->
          (* Sketch settings above the environment's camera/render panel. *)
          let changes, live, panel = inspector_panel ui panes.inspector (fun () ->
            let node_count = List.length (Edit_graph.inspect document)
              + List.length (Flow.Graph.inspect open_network.graph.values) in
            let display = Option.fold ~none:"none" ~some:(fun id ->
              Option.fold ~none:("#" ^ string_of_int id) ~some:Node.label
                (Edit_graph.find document ~node_id:id)) open_network.displayed in
            ignore (Pxui.Ui.inspector_header ui ~key:"network-header"
              ~title:(level_name value)
              ~detail:(Printf.sprintf "%d nodes · display %s"
                node_count display));
            let live = Pxui.Ui.inspector_toggle ui
                ~key:"live-cook" ~label:"Live update while dragging"
                value.live_cook in
            let changes = match Settings.fields unchanged with
              | [] -> []
              | fields ->
                  Pxui.Ui.scope ui "sketch-settings" (fun () ->
                    let _, _, width, _ = panes.inspector in
                    Option.value ~default:[] (Pxui.Ui.inspector_section ui
                      ~key:"sketch-settings-section" ~expanded:true "Settings"
                      (fun () -> Pxui_shell.Inspector.fields ui
                        ~width:(float width) fields))) in
            changes, live, camera_panel ()) in
          Some panel, [], changes, live
      | _ :: _ :: _ ->
          let () = inspector_panel ui panes.inspector (fun () ->
            ignore (Pxui.Ui.inspector_header ui ~key:"multi-header"
              ~title:(Printf.sprintf "%d nodes" (List.length selected_ids))
              ~detail:"Selected · ⌘G to group")) in
          None, [], [], value.live_cook
      | [node_id] ->
          let geometry = Edit_graph.find document ~node_id in
          let value_node = Flow.Graph.find open_network.graph.values ~node_id in
          let fields, label, kind, value_parameters = match geometry, value_node with
            | Some node, _ ->
                let fields = Node.parameter_fields node in
                let fields = if fields <> [] || Node.operation node = "flow_outputs"
                  then fields else
                  Result.value ~default:[] (Result.map (List.concat_map
                    (fun (parameter : Flow_sop.Port.parameter) -> parameter.fields))
                    (Flow_sop.Network.parameters open_network.graph
                      ~node_id)) in
                fields, Node.label node, Node.operation node, None
            | None, Some node -> Flow.Value_kind.fields node.parameters, node.label,
                Flow.Value_kind.key (Flow.Value_kind.kind node.parameters),
                Some node.parameters
            | None, None -> [], "#" ^ string_of_int node_id, "unknown", None in
          let interface_ports = match value.level, kind with
            | Document.Compound _, ("flow_inputs" | "flow_outputs") ->
                (match List.rev (Document.compound_names value.doc value.level) with
                 | name :: _ ->
                     (match Document.String_map.find_opt name value.doc.definitions with
                      | None -> []
                      | Some definition ->
                          if kind = "flow_inputs" then definition.spec.inputs
                          else definition.spec.outputs)
                 | [] -> [])
            | _ -> [] in
          let changes = inspector_panel ui panes.inspector (fun () ->
            Pxui.Ui.scope ui (Printf.sprintf "node.%d" node_id) (fun () ->
              let _, _, inspector_width, _ = panes.inspector in
              let inspector_width = float (max 1 inspector_width) in
              let header = Pxui.Ui.inspector_header ui
                  ~key:"flow-inspector-header" ~title:label
                  ~detail:(Printf.sprintf "%s/%s · #%d%s%s"
                    (Flow.Context.name open_network.context) kind node_id
                    (if Edit_graph.is_bypassed document ~node_id then " · muted" else "")
                    (if open_network.displayed = Some node_id then " · displayed" else "")) in
              let renamed, editing = Pxui.Ui.within ui header (fun () ->
                Pxui.Ui.value_field ui ~at:(8., 5.)
                  ~w:(inspector_width -. 22.) ~h:29. ~size:16
                  ~valid:(fun text -> String.trim text <> "")
                  "node-label" label) in
              if not editing then Pxui.Ui.draw_over ui header (fun paint (x, y, w, _) ->
                let theme = Pxui.Ui.theme ui in
                Pxui.Ui.Paint.fill paint ~x:(x +. 8.) ~y:(y +. 5.)
                  ~w:(w -. 16.) ~h:29. theme.input;
                Pxui.Ui.Paint.text paint ~at:(x +. 9., y +. 8.) ~size:16
                  ~color:theme.foreground renamed);
              let rename = if renamed = label then [] else
                [Pxui_graph.Rename_requested {node = node_id; label = renamed}] in
              let interface_edits =
                let rows = List.map (fun (port : Flow_sop.Network.interface_port) ->
                  let field : Editor_core.Param.field_view = {
                    name = port.name; label = port.label; description = None;
                    folder = ["Interface"]; impact = Editor_core.Param.Cook;
                    primary = false; vec3 = None;
                    kind = Editor_core.Param.Text_view;
                    default = Editor_core.Param.Text_value port.name;
                    current = Editor_core.Param.Text_value port.name } in
                  { Pxui_shell.Inspector.path = port.name; fields = [field];
                    shown = false; locked = true; drive = None; live = None;
                    components = []; split = None }) interface_ports in
                let renamed = if rows = [] then [] else
                  Pxui_shell.Inspector.flow_fields ui
                    ~expanded:["Interface"] ~width:inspector_width
                    ~actions:false rows
                  |> List.filter_map (function
                    | Pxui_shell.Inspector.Edited
                        (from, Editor_core.Param.Text_value into) ->
                        Some (Pxui_graph.Rename_interface_requested
                          {node = node_id; from; into})
                    | _ -> None) in
                renamed @ List.concat
                (List.mapi (fun index (port : Flow_sop.Network.interface_port) ->
                    let compatible_neighbor offset =
                      index + offset >= 0
                      && Option.fold ~none:false ~some:(fun
                           (candidate : Flow_sop.Network.interface_port) ->
                         (candidate.ty = Flow.Port_type.Geometry)
                           = (port.ty = Flow.Port_type.Geometry))
                           (List.nth_opt interface_ports (index + offset)) in
                    let can_up = compatible_neighbor (-1)
                    and can_down = compatible_neighbor 1 in
                    let up = can_up && Pxui.Ui.inspector_button ui
                      ~key:(Printf.sprintf "interface-up-%d" index)
                      ("Move " ^ port.label ^ " up") in
                    let down = can_down && Pxui.Ui.inspector_button ui
                      ~key:(Printf.sprintf "interface-down-%d" index)
                      ("Move " ^ port.label ^ " down") in
                    let remove = port.ty <> Flow.Port_type.Geometry
                      && Pxui.Ui.inspector_button ui
                        ~key:(Printf.sprintf "interface-remove-%d" index)
                        ("Unexport " ^ port.label) in
                    (if up then [Pxui_graph.Reorder_interface_requested
                          {node = node_id; name = port.name; delta = -1}]
                       else if down then [Pxui_graph.Reorder_interface_requested
                          {node = node_id; name = port.name; delta = 1}]
                       else [])
                    @ (if remove then [Pxui_graph.Unexport_requested
                          {node = node_id; name = port.name}] else []))
                    interface_ports) in
              (match geometry with
               | None -> ()
               | Some _ ->
                   let names = Option.value ~default:[]
                     (Edit_graph.node_slot_names document ~node_id) in
                   let inputs = Option.value ~default:[||]
                     (Edit_graph.inputs document ~node_id) in
                   if Array.length inputs > 0 then
                     ignore (Pxui.Ui.inspector_section ui
                       ~key:"flow-input-heading" ~expanded:true "Inputs"
                       (fun () -> Array.iteri (fun index input ->
                         let name = Option.value
                             ~default:("in" ^ string_of_int index)
                             (List.nth_opt names index) in
                         let source = match input with
                           | None -> "empty"
                           | Some id -> Option.fold
                               ~none:("#" ^ string_of_int id)
                               ~some:Node.label
                               (Edit_graph.find document ~node_id:id) in
                         Pxui.Ui.inspector_readout ui ~width:inspector_width
                           ~key:("flow-input-" ^ string_of_int index)
                           ~label:name ("← " ^ source)) inputs)));
              let rows = inspector_rows open_network.graph open_network.layout
                  (Option.value ~default:Flow_sop.Port.Map.empty applied)
                  node_id fields value_parameters in
              let edits = match rows with
                | Error diagnostic ->
                    Pxui.Ui.inspector_message ui ~key:"flow-diagnostic"
                      (Flow.Diagnostic.to_string diagnostic); []
                | Ok [] -> []
                | Ok rows ->
                    let expanded = fields |> List.filter_map (fun field ->
                      match field.Parameter.folder with [] -> None
                      | first :: _ -> Some first) |> List.sort_uniq String.compare in
                    Pxui_shell.Inspector.flow_fields ui ~expanded
                      ~width:inspector_width rows in
              rename @ interface_edits @ List.map (function
                | Pxui_shell.Inspector.Edited (path, value) ->
                    Pxui_graph.Set_parameter_requested {node = node_id; path; value}
                | Pinned (path, pinned) ->
                    Pxui_graph.Row_pinned {node = node_id; path; pinned}
                | Split (group, split) ->
                    Pxui_graph.Split_requested {node = node_id; group; split}
                | Reset path -> Pxui_graph.Value_disconnect_requested
                    {Flow_sop.Port.node = node_id; path}
                | Expression (path, text) -> Pxui_graph.Expression_requested
                    {target = {Flow_sop.Port.node = node_id; path}; text}) edits)) in
          None, changes, [], value.live_cook) in
    let graph_changes = graph_changes @ inspector_changes in
    let timeline_intents = if Pxui_shell.Layout.collapsed workspace Pxui_shell.Layout.Timeline
      then [] else Pxui.Ui.within ui timeline_root (fun () ->
        Pxui_shell.Timeline_bar.draw ui ~bounds:panes.timeline
          ~playing:(Sketch_support.Timeline.mode timeline = Sketch_support.Timeline.Playing)
          ~frame:(Sketch_support.Timeline.frame timeline)
          ~time:(Sketch_support.Timeline.time timeline)
          ~max_frame:value.timeline_frames) in
    let handle_edits, grab, picked =
      if Pxui_shell.Layout.collapsed workspace Pxui_shell.Layout.View then [], false, None
      else Pxui.Ui.within ui view_root (fun () ->
        view_handles ui ~selected ~space:(space { value with graph_view })
          ~bounds:panes.view) in
    let graph_view = match picked with
      | Some id when value.level = Document.Scene -> Pxui_graph.select id graph_view
      | Some _ | None -> graph_view in
    let handle_changes = match selected, handle_edits with
      | Some node, _ :: _ -> Some (Node.id node, handle_edits)
      | _ -> None in
    let context = match leader with
      | Leader.Pending _ -> Editor_core.Guide_context.Leader
      | Idle when value.prompt <> None || Pxui_graph.editing graph_view -> Search
      | Idle when Pxui_graph.hinting graph_view -> Hints
      | Idle when projection value = List_view -> List
      | Idle when Pxui_graph.hovered_row graph_view <> None -> Row
      | Idle when Pxui_graph.selected_wire graph_view -> Wire
      | Idle -> (match Pxui_graph.selected_nodes graph_view with
          | [] -> Canvas | [_] -> Node | _ -> Multi) in
    let commands = Editor_core.Command.for_guide keymap ~focus ~context in
    let hide_guide = status_box { value with workspace; status_fps; graph_view; guide; focus }
        ui frame ~render_status ~context ~commands in
    if graph_shown then Option.iter (fun (text, _) ->
      Pxui_shell.Status_bar.hud ui ~bounds:panes.graph ~text) hud;
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
      | Pxui_shell.Layout.View -> panes.view | Graph -> panes.graph
      | Inspector -> panes.inspector | Timeline -> panes.timeline in
    Pxui_shell.Chrome.focus ui ~bounds;
    { workspace; focus; pane_keys; graph_view; tree; document = (network value).graph; edit_error = value.edit_error;
      effects = Parameter.no_effects;
      timeline_intents; frame_request; prompt = None; prompt_intent = None;
      panel; grab; settings = unchanged; touched = false; placed = []; pasted = [];
      opened; live_cook; label = "Edit";
      graph_changes; tree_intents = list_intents; text_toggle; open_graph;
      settings_changes;
      handle_changes; hide_guide } in
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
    | Guide_keys -> Some Keys
    | Command_palette -> Some (Palette "")
    | _ -> prompt) value.prompt actions in
  let prompt_panel ui prompt =
    let module Ui = Pxui.Ui in
    let next = match prompt with
    | None -> None, None
    | Some Keys ->
        let commands = List.filter (fun (command : Leader.command) -> match command.action with
          | List_command _ | Frame_tile -> false | _ -> true) value.keymap in
        (if Pxui_shell.Which_key.sheet ui commands then Some Keys else None), None
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
            if command.scope <> None && command.scope <> Some focus then seen else
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
    if fst next = None && prompt <> None then Ui.dismiss_popup ui;
    next in
  let result = match Pxui_shell.Shell.frame value.ui frame
      ~visible:all_ui_visible ~overlay:leader_panel
      ~body:(fun ui ->
        let prompt, prompt_intent = prompt_panel ui initial_prompt in
        let result = build ui in
        { result with prompt; prompt_intent }) with
    | Some result -> result
    | None ->
      { workspace; focus; pane_keys = []; graph_view; tree; document = (network value).graph;
        edit_error = value.edit_error;
        effects = Parameter.no_effects; timeline_intents = [];
        frame_request = initial_frame_request; prompt = initial_prompt;
        prompt_intent = None; panel = None; grab = false;
        settings = value.doc.settings; touched = false; placed = []; pasted = [];
        opened = None; live_cook = value.live_cook; label = "Edit";
        graph_changes = command_changes; tree_intents = list_intents;
        text_toggle = false; open_graph;
        settings_changes = []; handle_changes = None; hide_guide = false } in
  let guide = guide && not result.hide_guide in
  let guide_error = if guide = value.guide then None else
    match save_guide value.preferences guide with
    | Ok () -> None | Error message -> Some ("Guide preference not saved: " ^ message) in
  (* The one reduction phase: panes have finished constructing their boxes. *)
  let document, graph_view, edit_error, editor_effects, placed, pasted = List.fold_left
      (Doc.apply (catalog value value.level))
      ((network value).graph, result.graph_view, value.edit_error, Parameter.no_effects, [], [])
      result.graph_changes in
  let tree_document = document in
  let tree_graph_view = graph_view in
  let document, graph_view, tree, opened, tree_label, _ = List.fold_left
      (apply_tree value) (document, graph_view, result.tree, result.opened, None, rows)
      result.tree_intents in
  let placed = List.concat_map (function
    | Pxui_shell.Tree.Reorder { ids; delta } when value.level = Document.Scene ->
        scene_reorder_pairs tree_document.geometry rows ids delta
        |> List.concat_map (fun (id, neighbour) -> [id; neighbour])
    | Move { ids; _ } | Reorder { ids; _ } | Delete ids -> ids
    | _ -> []) result.tree_intents @ placed in
  let tree = match List.find_map (function
      | Pxui_graph.Add_requested _ -> Pxui_graph.selected graph_view
      | _ -> None) result.graph_changes with
    | Some id when projection value = List_view -> Pxui_shell.Tree.rename id "" tree
    | _ -> tree in
  let touched = tree_document != document || tree_graph_view != graph_view || List.exists (function
    | Pxui_graph.Selected _ | View_changed | Connection_selected _
    | Frame_camera_requested _ | Open_requested _ | Notice _ -> false
    | _ -> true) result.graph_changes in
  let apply_changes (document, effects, error) = function
    | None -> document, effects, error
    | Some (node_id, values) ->
        (match Doc.apply_parameters document ~node_id values with
         | Ok (document, changed) -> document, Parameter.union_effects effects changed, error
         | Error message -> document, effects, Some message) in
  let document, parameter_effects, edit_error =
    apply_changes (document, Parameter.no_effects, edit_error) result.handle_changes in
  let settings, settings_effects, edit_error = match result.settings_changes with
    | [] -> value.doc.settings, Parameter.no_effects, edit_error
    | changes -> (match Settings.apply value.doc.settings changes with
      | Ok (settings, effects) -> settings, effects, edit_error
      | Error message -> value.doc.settings, Parameter.no_effects, Some message) in
  let node_effects effects = match value.level with
    | Document.Inside id when kind value id = Some "geometry" -> effects
    | Compound _ -> effects
    | Inside _ | Scene -> { effects with Parameter.cook = false } in
  let label = match List.find_map intent_label result.graph_changes, tree_label with
    | Some label, _ | None, Some label -> label
    | None, None when settings != value.doc.settings -> "Settings"
    | None, None -> match result.handle_changes with
      | Some (id, _) ->
          "Edit " ^ Option.fold ~none:(string_of_int id) ~some:Node.label
            (Edit_graph.find document.geometry ~node_id:id)
      | None -> "Edit" in
  let result = { result with document; graph_view; tree; opened; edit_error;
    effects = Parameter.union_effects (node_effects
      (Parameter.union_effects editor_effects parameter_effects)) settings_effects;
    settings; placed; pasted; touched; label } in
  let timeline, timeline_changes = List.fold_left (fun (timeline, changes) intent ->
    let next, emitted = match intent with
      | Pause_toggle -> Sketch_support.Timeline.toggle_pause timeline
      | Stop_playback -> Sketch_support.Timeline.stop timeline
      | Reset_playback -> Sketch_support.Timeline.reset timeline
      | Seek_playback frame -> Sketch_support.Timeline.seek timeline ~frame in
    next, changes @ emitted) (timeline, timeline_changes) result.timeline_intents in
  let prompt, notice, loaded = match result.prompt_intent with
    | None -> result.prompt, (match List.find_map (function
        | Pxui_graph.Notice message -> Some message | _ -> None) result.graph_changes with
        | Some _ as notice -> notice | None -> value.notice), None
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
         | Ok preset ->
             (match Document.resolve_level ~scene_level:value.scene_level preset.doc Document.Scene with
              | Ok _ -> result.prompt, Some ("Loaded preset " ^ name), Some preset
              | Error message -> result.prompt, Some ("Preset rejected: " ^ message), None)
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
  let geometry_port node index =
    let names = Edit_graph.node_slot_names result.document.geometry ~node_id:node in
    node, Option.value ~default:("in" ^ string_of_int index)
      (Option.bind names (fun names -> List.nth_opt names index)) in
  let next = match loaded with
    | Some (preset : Preset.loaded) -> preset.doc
    | None ->
        let edited = if laid_out
          then Network_view.of_view { current with graph = result.document } result.graph_view
          else if result.document == current.graph && not result.touched then current
          else
            let ports = List.concat_map (function
              | Pxui_graph.Bend_changed { node; slot } ->
                  [geometry_port node slot]
              | Value_bind_requested {target; _} | Wireless_changed {target; _} ->
                  [target.node, target.path]
              | Value_disconnect_requested target -> [target.node, target.path]
              | Row_reset_requested target -> [target.node, target.path]
              | Expression_requested {target; _} -> [target.node, target.path]
              | Fold_requested target | Unfold_requested target ->
                  [target.node, target.path]
              | Disconnect_requested c ->
                  [geometry_port c.consumer c.input_index]
              | Cut_wires_requested cs -> List.map (fun (c : Edit_graph.connection) ->
                  geometry_port c.consumer c.input_index) cs
              | Delete_nodes_requested ids | Dissolve_nodes_requested ids ->
                  (List.map fst (Editor_core.Network_layout.Port_map.bindings
                    current.layout.bends)
                   @ Editor_core.Network_layout.Port_set.elements
                       current.layout.wireless)
                  |> List.sort_uniq compare
                  |> List.filter (fun (id, path) ->
                    List.mem id ids || not (Document.wire_exists result.document
                      (id, path)))
              | _ -> []) result.graph_changes in
            Network_view.edit current result.document result.graph_view result.placed ports in
        let doc = if edited == current then present
          else Document.with_network present value.level edited in
        let doc = if value.level = Document.Scene && edited != current then
            seed_networks value (Document.prune (Document.copy_networks doc result.pasted))
              (List.map (fun (info : Edit_graph.node_info) -> info.id)
                (Edit_graph.inspect edited.graph.geometry))
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
  let next, world_added = match Objects.ids "world" next.scene.graph.geometry with
    | [] when List.mem Leader.Go_world actions && value.scene_level ->
        (match add_world next daylight with Ok doc -> doc, true | Error _ -> next, false)
    | _ -> next, false in
  let next, result = if List.mem Leader.Group actions && Option.is_none loaded then
    let selected = Pxui_graph.selected_nodes result.graph_view in
    let positions = List.filter_map (fun id ->
      Option.map (fun (x, y) -> id, x, y)
        (Pxui_graph.node_position result.graph_view id)) selected in
    (match Document.group next value.level ~selected ~positions with
     | Error diagnostic -> next, {result with
         edit_error = Some (Flow.Diagnostic.to_string diagnostic)}
     | Ok (next, instance) ->
         let network = Option.get (Document.network next value.level) in
         let graph_view = Network_view.to_view network result.graph_view
           |> Pxui_graph.select instance in
         next, {result with graph_view; document = network.graph;
           label = "Group"; effects = Parameter.union_effects
             result.effects Doc.cook_effects})
    else next, result in
  let next, result = if List.mem Leader.Ungroup actions && Option.is_none loaded then
    match Pxui_graph.selected_nodes result.graph_view with
    | [instance_id] ->
        (match Document.ungroup next value.level ~instance_id with
         | Error diagnostic -> next, {result with
             edit_error = Some (Flow.Diagnostic.to_string diagnostic)}
         | Ok (next, mapping) ->
             let network = Option.get (Document.network next value.level) in
             let graph_view = Network_view.to_view network result.graph_view
               |> Pxui_graph.select_nodes (List.map snd mapping) in
             next, {result with graph_view; document = network.graph;
               label = "Ungroup"; effects = Parameter.union_effects
                 result.effects Doc.cook_effects})
    | _ -> next, {result with edit_error = Some
        "Select one compound instance to ungroup"}
    else next, result in
  let unique_request = List.find_map (function
    | Pxui_graph.Make_unique_requested id -> Some id | _ -> None)
    result.graph_changes in
  let unique_request = match unique_request with
    | Some _ -> unique_request
    | None when List.mem Leader.Make_unique actions ->
        (match Pxui_graph.selected_nodes result.graph_view with
         | [id] -> Some id | _ -> None)
    | None -> None in
  let next, result = if Option.is_none loaded then match unique_request with
    | None ->
        if List.mem Leader.Make_unique actions then next, {result with
          edit_error = Some "Select one compound instance to make unique"}
        else next, result
    | Some instance_id ->
        (match Document.make_unique next value.level ~instance_id with
         | Error diagnostic -> next, {result with
             edit_error = Some (Flow.Diagnostic.to_string diagnostic)}
         | Ok (next, _) ->
             let network = Option.get (Document.network next value.level) in
             let graph_view = Network_view.to_view network result.graph_view
               |> Pxui_graph.select instance_id in
             next, {result with graph_view; document = network.graph;
               label = "Make unique"; effects = Parameter.union_effects
                 result.effects Doc.cook_effects})
    else next, result in
  let rename_request = List.find_map (function
    | Pxui_graph.Rename_interface_requested {node; from; into} ->
        Some (node, from, into)
    | _ -> None) result.graph_changes in
  let next, result = if Option.is_none loaded then match rename_request with
    | None -> next, result
    | Some (node, from, into) ->
        let side = match Edit_graph.find result.document.geometry ~node_id:node with
          | Some marker when Node.operation marker = "flow_inputs" ->
              Some Document.Input
          | Some marker when Node.operation marker = "flow_outputs" ->
              Some Document.Output
          | _ -> None in
        (match side, List.rev (Document.compound_names next value.level) with
         | Some side, definition_name :: _ ->
             (match Document.rename_interface_port next ~definition_name
                 ~side ~from ~into with
              | Error diagnostic -> next, {result with
                  edit_error = Some (Flow.Diagnostic.to_string diagnostic)}
              | Ok next ->
                  let network = Option.get (Document.network next value.level) in
                  let graph_view = Network_view.to_view network result.graph_view in
                  next, {result with graph_view; document = network.graph;
                    label = "Rename interface port";
                    effects = Parameter.union_effects
                      result.effects Doc.cook_effects})
         | _ -> next, {result with edit_error =
             Some "Select an Inputs or Outputs marker inside a compound"})
    else next, result in
  let reorder_request = List.find_map (function
    | Pxui_graph.Reorder_interface_requested {node; name; delta} ->
        Some (node, name, delta)
    | _ -> None) result.graph_changes in
  let next, result = if Option.is_none loaded then match reorder_request with
    | None -> next, result
    | Some (node, name, delta) ->
        let name = match rename_request with
          | Some (renamed_node, from, into)
            when renamed_node = node && from = name
              && Option.is_none result.edit_error -> into
          | _ -> name in
        let side = match Edit_graph.find result.document.geometry ~node_id:node with
          | Some marker when Node.operation marker = "flow_inputs" ->
              Some Document.Input
          | Some marker when Node.operation marker = "flow_outputs" ->
              Some Document.Output
          | _ -> None in
        (match side, List.rev (Document.compound_names next value.level) with
         | Some side, definition_name :: _ ->
             (match Document.reorder_interface next ~definition_name
                 ~side ~name ~delta with
              | Error diagnostic -> next, {result with
                  edit_error = Some (Flow.Diagnostic.to_string diagnostic)}
              | Ok next ->
                  let network = Option.get (Document.network next value.level) in
                  let graph_view = Network_view.to_view network result.graph_view in
                  next, {result with graph_view; document = network.graph;
                    label = "Reorder interface";
                    effects = Parameter.union_effects
                      result.effects Doc.cook_effects})
         | _ -> next, {result with edit_error =
             Some "Select an Inputs or Outputs marker inside a compound"})
    else next, result in
  let export_request = List.find_map (function
    | Pxui_graph.Export_requested target -> Some target
    | _ -> None) result.graph_changes in
  let next, result = if Option.is_none loaded then match export_request with
    | None -> next, result
    | Some target ->
        (match Document.export_parameter next value.level ~target with
         | Error diagnostic -> next, {result with
             edit_error = Some (Flow.Diagnostic.to_string diagnostic)}
         | Ok (next, name) ->
             let network = Option.get (Document.network next value.level) in
             let graph_view = Network_view.to_view network result.graph_view in
             next, {result with graph_view; document = network.graph;
               label = "Export " ^ name;
               effects = Parameter.union_effects
                 result.effects Doc.cook_effects})
    else next, result in
  let unexport_request = List.find_map (function
    | Pxui_graph.Unexport_requested {node; name} -> Some (node, name)
    | _ -> None) result.graph_changes in
  let next, result = if Option.is_none loaded then match unexport_request with
    | None -> next, result
    | Some (node, name) ->
        let name = match rename_request with
          | Some (renamed_node, from, into)
            when renamed_node = node && from = name
              && Option.is_none result.edit_error -> into
          | _ -> name in
        let side = match Edit_graph.find result.document.geometry ~node_id:node with
          | Some marker when Node.operation marker = "flow_inputs" ->
              Some Document.Input
          | Some marker when Node.operation marker = "flow_outputs" ->
              Some Document.Output
          | _ -> None in
        (match side, List.rev (Document.compound_names next value.level) with
         | Some side, definition_name :: _ ->
             (match Document.unexport_port next ~definition_name
                 ~side ~name with
              | Error diagnostic -> next, {result with
                  edit_error = Some (Flow.Diagnostic.to_string diagnostic)}
              | Ok next ->
                  let network = Option.get (Document.network next value.level) in
                  let graph_view = Network_view.to_view network result.graph_view in
                  next, {result with graph_view; document = network.graph;
                    label = "Unexport " ^ name;
                    effects = Parameter.union_effects
                      result.effects Doc.cook_effects})
         | _ -> next, {result with edit_error =
             Some "Select an Inputs or Outputs marker inside a compound"})
    else next, result in
  let next, result, compound_error = if next == present then next, result, None else
    match Document.allocate_compiled_ids next with
    | Ok next -> next, result, None
    | Error diagnostic ->
        let previous = network value in
        present, {result with
          graph_view = Network_view.to_view previous result.graph_view;
          document = previous.graph},
        Some (Flow.Diagnostic.to_string diagnostic) in
  let input = Pxui.Ui.input ?owner:(List.find_map (fun (key, column) ->
      if column = Pxui_shell.Layout.View then Some key else None) result.pane_keys) value.ui in
  let dragging = Frame.mouse_down Input.LeftButton frame || Frame.has_event (function
    | Event.MouseReleased (Input.LeftButton, _) -> true | _ -> false) frame in
  let gesture = if not dragging || Option.is_some loaded || laid_out
      || world_added || world_label <> None then None else
    match List.find_map (function
      | Pxui_graph.Bend_changed { node; slot } ->
          Some (Printf.sprintf "graph.bend:%s:%d:%d" (level_key value.level) node slot)
      | Set_parameter_requested { node; path; _ } ->
          Some (Printf.sprintf "graph.scrub:%s:%d:%s" (level_key value.level) node path)
      | _ -> None) result.graph_changes with
    | Some key -> Some key
    | None ->
    let graph = List.filter_map (function
      | Pxui_graph.Node_moved id -> Some [id]
      | Nodes_moved ids -> Some ids
      | change when intent_label change <> None -> Some []
      | _ -> None) result.graph_changes in
    match graph, result.tree_intents, result.handle_changes,
        result.settings_changes with
    | [], [], Some (id, changes), [] ->
        Some (parameter_gesture "handle" value.level id changes)
    | [], [], None, (_ :: _ as changes) ->
        Some (parameter_gesture "settings" value.level (-1) changes)
    | (_ :: _ as moved), [], None, [] when List.for_all (( <> ) []) moved ->
        Some ("move/" ^ level_key value.level ^ "/"
          ^ String.concat "/" (List.map string_of_int
            (List.sort_uniq Int.compare (List.concat moved))))
    | _ -> None in
  let history = if next == present then value.history
    else commit
        ~label:(if Option.is_some loaded then "Load preset"
          else if world_added then "Add World"
          else if world_label <> None then Option.get world_label
          else if laid_out then "Layout" else result.label)
        ~merge:(if List.exists (function Pxui_graph.Level_changed _ | Split_requested _
          | Row_pinned _ -> true | _ -> false)
            result.graph_changes && gesture = None then
          Editor_core.History.Burst { key = "layout.level:" ^ level_key value.level;
            at = frame.time; window = 1.0 }
          else Option.fold ~none:Editor_core.History.Step
            ~some:(fun key -> Editor_core.History.Gesture key) gesture) next value.history in
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
  let level = Document.resolve_level ~scene_level:value.scene_level doc
      (if Option.is_some loaded then Document.Scene else value.level)
    |> Result.get_ok in
  let value' = { value with doc; level; workspace = result.workspace } in
  let graph_view = if level <> value.level then view_of value' level frame
    else if undone || Option.is_some loaded then
      Network_view.to_view (network value') result.graph_view
      |> Pxui_graph.with_flagged (if level = Document.Scene then doc.active_camera else None)
    else
      let network = network value' in
      Pxui_graph.with_document network.graph result.graph_view
      |> Pxui_graph.with_flagged (if level = Document.Scene then doc.active_camera else None)
      |> fun view -> match network.displayed with
        | Some id when Pxui_graph.viewed view <> id -> Pxui_graph.view id view
        | _ -> view in
  let graph_view = if doc.definitions == value.doc.definitions then graph_view else
    Pxui_graph.with_definitions (Document.flow_definitions doc) graph_view in
  (* Entering and leaving levels: i / double-click / list activation, u. *)
  let up = if List.mem Leader.Up actions then Document.parent_level level else None in
  let target = match List.find_opt (function
      | Leader.Enter | Up | Go_world -> true | _ -> false) actions, result.opened with
    | Some Leader.Up, _ -> (match level with
      | Inside _ when value.scene_level -> Some Document.Scene
      | Compound _ -> Option.map fst up
      | Scene | Inside _ -> None)
    | Some Leader.Go_world, _ ->
        Option.map (fun id -> Document.Inside id)
          (List.find_opt (enterable value') (Objects.ids "world" doc.scene.graph.geometry))
    | Some Leader.Enter, _ | _, Some _ ->
        let candidate = match result.opened with
          | Some id -> Some id | None -> Pxui_graph.selected graph_view in
        (match level, candidate with
         | Document.Scene, Some id when enterable value' id -> Some (Document.Inside id)
         | (Inside _ | Compound _), Some id -> Document.enter_compound doc level id
         | _ -> None)
    | _ -> None in
  let graph_view = match result.open_graph with
    | Some id -> Pxui_graph.select id graph_view
    | None -> graph_view in
  let value' = { value' with graph_view; tree = result.tree } in
  let value' = match target with
    | Some level -> open_level value' level frame
    | None -> value' in
  let value' = match up with
    | Some (parent, instance) when value'.level = parent ->
        {value' with graph_view = Pxui_graph.select instance value'.graph_view}
    | Some _ | None -> value' in
  (* In the World, Space l flips the view pane to the lat-long map. *)
  let map_view = if List.mem Leader.Toggle_projection actions && in_world value'
    then not value'.map_view else value'.map_view && in_world value' in
  let value' = { value' with map_view } in
  let projections = if result.open_graph <> None then
      Level_map.add value'.level Graph_view value'.projections
    else if List.mem Leader.Toggle_projection actions && not (in_world value') then
      Level_map.add value'.level
        (match projection value' with Graph_view -> List_view
          | List_view -> Text_view | Text_view -> Graph_view) value'.projections
    else value'.projections in
  (* Switching to the graph frames it, so its tiles are on screen. *)
  let graph_view = if result.open_graph <> None then
      fst (Pxui_graph.run_command value'.graph_view Pxui_graph.Frame_selection)
    else if projection { value' with projections } = Graph_view
        && projection value' <> Graph_view
      then fst (Pxui_graph.run_command value'.graph_view Pxui_graph.Frame_all)
      else value'.graph_view in
  let qualified_text = if result.text_toggle then
      Level_map.add value.level
        (not (Option.value ~default:false
          (Level_map.find_opt value.level value.qualified_text))) value.qualified_text
    else value.qualified_text in
  let value' = { value' with projections; qualified_text; text_cache;
    rows = rows_cache; graph_view;
    live_cook = result.live_cook } in
  let frame_request = match result.frame_request, value'.level with
    | Some node, Inside id when kind value' id = Some "geometry" -> Some (id, node)
    | _ -> None in
  let cooked = Cook.update ~live:result.live_cook
      ~definitions:doc.definitions ~compiled_ids:doc.compiled_ids
      value.cook ~settings:doc.settings
      ~objects:(geometry_objects value')
      ~edit_error:(match result.edit_error with Some _ -> result.edit_error
        | None -> compound_error) ~effects
      ~timeline_changes ~timeline ~frame ~frame_request in
  let value' = match value'.level with
    | Document.Inside id ->
        let applied = Option.map (fun resolved -> resolved.Flow_sop.Value_lane.applied)
            (Cook.applied cooked.cook id) in
        {value' with graph_view = Pxui_graph.with_applied
          (Option.value ~default:Flow_sop.Port.Map.empty applied) value'.graph_view}
    | Scene | Compound _ -> value' in
  (* Framing: local bounds move into the world with their object; at the
     scene level [F] frames every cooked object. *)
  let lower (a : Vec3.t) (b : Vec3.t) =
    Vec3.create (Float.min a.x b.x) (Float.min a.y b.y) (Float.min a.z b.z)
  and upper (a : Vec3.t) (b : Vec3.t) =
    Vec3.create (Float.max a.x b.x) (Float.max a.y b.y) (Float.max a.z b.z) in
  let world_bounds id (lo, hi) =
    let matrix = Objects.world doc.scene.graph.geometry id in
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
      status_fps; status_fps_at; history; guide; hud; focus = result.focus;
      pane_keys = result.pane_keys; leader; held_keys; prompt;
      queued = (match result.prompt_intent with Some (Run_action action) -> [action] | _ -> []);
      notice = if guide_error <> None then guide_error
        else if document_changed && Option.is_none loaded && not undone then None
        else notice };
    effects; prepared_changed = cooked.prepared_changed;
    scene_changed = doc.scene != value.doc.scene || cooked.prepared_changed;
    framed;
    loaded_view = Option.map (fun (preset : Preset.loaded) -> preset.view) loaded;
    actions; panel = result.panel;
    input }

(* Environment-owned scene edits (camera bookkeeping, follow viewport).
   [`Reset] starts the history, [`Amend] folds into the present entry, and
   [`View time] coalesces a burst of view edits (a drag, a wheel gesture)
   into one undo entry. *)
let scene_edit value mode ?(active_camera = value.doc.active_camera) scene =
  let doc = { value.doc with scene = { value.doc.scene with graph = Result.get_ok (Flow_sop.Network.with_geometry scene value.doc.scene.graph);
      displayed = Document.displayed_of ?previous:value.doc.scene.displayed (Flow_sop.Network.of_geometry scene) None };
    active_camera } in
  let history = match mode with
    | `Reset -> Editor_core.History.create doc
    | `Amend -> commit ~merge:Repair doc value.history
    | `View time -> commit ~label:"Move camera"
        ~merge:(Burst { key = "view"; at = time; window = 0.25 })
        doc value.history in
  { value with doc; history;
    graph_view = if value.level <> Document.Scene then value.graph_view
      else Pxui_graph.with_document doc.scene.graph value.graph_view
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
    history = commit ~label:"Settings" doc value.history }

(* The scene's World at timeline [time] (the day cycle advances with it). *)
let world value ~time = match Objects.ids "world" (scene value) with
  | id :: _ when Edit_graph.is_bypassed (scene value) ~node_id:id -> None
  | id :: _ ->
      Option.bind (Edit_graph.find (scene value) ~node_id:id) (fun node ->
        Option.bind (Document.Layout.find_opt id value.doc.Document.networks)
          (fun network -> Layers.to_world ~time node network))
  | [] -> None

(* Visible objects' world transforms with their latest cook. *)
let placed_pieces ?(render = false) value =
  List.filter_map (fun (piece : _ Cook.piece) ->
    match Edit_graph.find (scene value) ~node_id:piece.id with
    | Some node when Objects.visible node
        && not (Edit_graph.is_bypassed (scene value) ~node_id:piece.id)
        && (not render || Objects.flag "render" node) ->
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
      match Edit_graph.apply_parameters network.graph.geometry ~node_id values with
      | Error _ -> value
      | Ok (graph, _) ->
          let doc = Document.with_network value.doc level { network with graph = Result.get_ok (Flow_sop.Network.with_geometry graph network.graph) } in
          { value with doc;
            history = commit ~label ~merge:(Gesture
              (parameter_gesture label level node_id values)) doc value.history;
            graph_view = if level = value.level
              then Pxui_graph.with_document (Option.get (Document.network doc level)).graph value.graph_view else value.graph_view }
