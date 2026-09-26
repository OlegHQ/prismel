open Prismel
open Procedural
open Common

type bounds = Cook.bounds

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
  document : Edit_graph.t;
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
  label : string;  (* names this frame's document change in history *)
}

type 'prepared t = {
  code_graph : Graph.t;
  presets : string;  (* preset directory *)
  name : string;  (* sketch name recorded in presets *)
  prompt : prompt option;
  notice : string option;
  graph : Graph.t;
  displayed_graph : Graph.t;
  document : Edit_graph.t;
  factories : Edit_graph.factory list;
  graph_view : Pxui_graph.t;
  displayed_id : int;
  ui : Pxui.Ui.t;
  workspace : Workspace.t;
  timeline : Sketch_support.Timeline.t;
  cook : 'prepared Cook.t;
  edit_error : string option;
  status_fps : int option;
  status_fps_at : float;
  settings : Settings.t;
  history : Document.t Editor_core.History.t;
  focus : Workspace.column;
  pane_keys : (int * Workspace.column) list;
  leader : Leader.state;
  keymap : Leader.binding list;
  timeline_frames : int;
  queued : Leader.action list;  (* picked in the palette, run next frame *)
}

type ('prepared, 'panel) update = {
  core : 'prepared t;
  effects : Parameter.effects;
  prepared_changed : bool;
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

let create ?(settings = Settings.none) ?(keymap = Leader.keymap) ?(seed_document = fun _ document -> document)
    ?(name = "sketch") ?presets ?(timeline_frames = 240)
    ?(layout = Pxui_shell.Layout.default) ?(factories = [])
    ?(seed = 0L) ?(grain = 16_384)
    ?domains ?(max_entries = 32)
    ?(max_payload_bytes = 256 * 1024 * 1024)
    ~graph ~prepare () =
  Result.map (fun cook ->
      let workspace = Workspace.create layout in
      let panes = Workspace.geometry workspace initial_frame in
      let gx, gy, gw, gh = panes.graph in
      let document = seed_document factories (Edit_graph.of_graph graph) in
      let graph_view = Pxui_graph.create_document ~x:gx ~y:gy
          ~width:(max 1 gw) ~height:(max 1 gh)
          ~catalog:(Pxui_graph.catalog_of_factories factories)
          ~flaggable:(fun info -> info.Edit_graph.operation = "camera") document in
      let presets = match presets with
        | Some directory -> directory
        | None -> Filename.concat (Filename.concat
            (Option.value ~default:"." (Sys.getenv_opt "HOME")) ".prismel")
            (Preset.sanitize name) in
      { code_graph = graph; presets; name; prompt = None; notice = None;
        graph; displayed_graph = graph; document; factories; graph_view;
        displayed_id = Node.id graph;
        ui = Pxui.Ui.create (); workspace;
        timeline = Sketch_support.Timeline.create (); cook;
        edit_error = None; status_fps = None;
        status_fps_at = Float.neg_infinity;
        settings;
        history = Editor_core.History.create
            (Document.of_view document graph_view settings);
        focus = Workspace.View; pane_keys = []; leader = Leader.Idle;
        keymap; timeline_frames = max 1 timeline_frames; queued = [] })
      (Cook.create ~prepare ~seed ~grain ?domains ~max_entries
        ~max_payload_bytes ())

let graph value = value.graph
let document value = value.document
let settings value = value.settings
let prepared value = value.cook.Cook.prepared
let timeline value = value.timeline
let selected_node value = Option.bind (Pxui_graph.selected value.graph_view)
    (fun node_id -> Edit_graph.find value.document ~node_id)
let displayed_node value = value.displayed_graph
let panes value frame = Workspace.geometry value.workspace frame
let column_visible value column = not (Workspace.collapsed value.workspace column)

let truncate limit text = if String.length text <= limit then text
  else String.sub text 0 (limit - 3) ^ "..."

let status_text value =
  let viewing = Node.label (displayed_node value) in
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
  cook ^ " · viewing " ^ viewing

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
let apply_action (frame : Frame.t) (workspace, graph_view, timeline, changes) action =
  let module T = Sketch_support.Timeline in
  let timeline_step step = let timeline, more = step timeline in
    workspace, graph_view, timeline, changes @ more in
  match action with
  | Leader.Toggle_timeline ->
      Workspace.toggle Workspace.Timeline workspace, graph_view, timeline, changes
  | Toggle_graph ->
      Workspace.toggle Workspace.Graph workspace, graph_view, timeline, changes
  | Toggle_inspector ->
      Workspace.toggle Workspace.Inspector workspace, graph_view, timeline, changes
  | Open_camera ->
      Workspace.expand Workspace.Inspector workspace,
      Pxui_graph.clear_selection graph_view, timeline, changes
  | Play_pause -> timeline_step T.toggle_pause
  | Reset -> timeline_step T.reset
  | Stop -> timeline_step T.stop
  | Add_node ->
      let gx, gy, gw, gh = (Workspace.geometry workspace frame).graph in
      let mx, my = frame.mouse in
      let at = if mx >= float gx && my >= float gy &&
          mx < float (gx + gw) && my < float (gy + gh)
        then int_of_float mx, int_of_float my
        else gx + (gw / 3), gy + (gh / 3) in
      Workspace.expand Workspace.Graph workspace,
      Pxui_graph.open_menu_at at graph_view, timeline, changes
  | Layout -> workspace, Pxui_graph.optimize_layout graph_view, timeline, changes
  | Frame_tile -> workspace, Pxui_graph.frame_viewed graph_view, timeline, changes
  | Hide_ui | Look_through | Fly | Save_preset | Browse_presets
  | Graph_command _ | Frame_camera | Undo | Redo | Command_palette | Sketch_command _ ->
      workspace, graph_view, timeline, changes

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
  | Selected _ | View_changed | Connection_selected _ | Frame_camera_requested _ -> None

let update value ~all_ui_visible ~text_focus ~camera_panel ~view_handles
    ~render_status ~view_state (frame : Frame.t) =
  let text_focus = text_focus || value.prompt <> None in
  let focus = if all_ui_visible then
      match Pxui.Ui.last_press_within value.ui frame
          (List.map fst value.pane_keys) with
      | Some key -> Option.value ~default:value.focus
          (List.assoc_opt key value.pane_keys)
      | None -> value.focus
    else value.focus in
  let keymap = if all_ui_visible
      && not (Workspace.collapsed value.workspace Workspace.Graph)
    then value.keymap else List.filter (fun binding ->
      match binding.Editor_core.Keymap.action with
      | Leader.Graph_command _ | Leader.Frame_camera -> false
      | _ -> true) value.keymap in
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
  let workspace, graph_view, timeline, timeline_changes = List.fold_left
      (apply_action frame)
      (value.workspace, value.graph_view, timeline, timeline_changes) actions in
  let graph_view, command_changes = List.fold_left (fun (graph_view, changes) ->
    function
    | Leader.Graph_command command when all_ui_visible
        && not (Workspace.collapsed workspace Workspace.Graph) ->
        let graph_view, emitted = Pxui_graph.run_command graph_view command in
        graph_view, changes @ emitted
    | _ -> graph_view, changes) (graph_view, []) actions in
  (* ponytail: seeking recooks the pure graph at the target frame; state a
     sketch threads through [run_state] outside the graph is not replayed. *)
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
           (not (Workspace.collapsed workspace Workspace.Graph)) in
    let graph_view, graph_changes = if Pxui_graph.visible graph_view
      then Pxui.Ui.within ui graph_root (fun () ->
        Pxui_graph.update graph_view ui shortcut_frame)
      else graph_view, [] in
    let graph_changes = command_changes @ graph_changes in
    let frame_request = List.fold_left (fun request -> function
      | Pxui_graph.Frame_camera_requested id -> Some id
      | _ -> request) initial_frame_request graph_changes in
    let document, graph_view, edit_error, editor_effects = List.fold_left
        (Doc.apply value.factories)
        (value.document, graph_view, value.edit_error, Parameter.no_effects)
        graph_changes in
    let inspector_visible = not (Workspace.collapsed workspace Workspace.Inspector) in
    let selected = Option.bind (Pxui_graph.selected graph_view)
        (fun node_id -> Edit_graph.find document ~node_id) in
    let touched = List.exists (function
      | Pxui_graph.Selected _ | View_changed | Connection_selected _
      | Frame_camera_requested _ -> false
      | _ -> true) graph_changes in
    let unchanged = value.settings in
    let panel, document, parameter_effects, edit_error, settings =
      Pxui.Ui.within ui inspector_root (fun () -> match selected with
      | None when not inspector_visible ->
          None, document, Parameter.no_effects, edit_error, unchanged
      | None ->
          (* Sketch settings above the environment's camera/render panel. *)
          let edited, panel = inspector_panel ui panes.inspector (fun () ->
            let edited = match Settings.fields value.settings with
              | [] -> Ok (value.settings, Parameter.no_effects)
              | fields ->
                  Pxui.Ui.scope ui "sketch-settings" (fun () ->
                    Pxui.Ui.label ui "Settings";
                    match Pxui_shell.Inspector.fields ui fields with
                    | [] -> Ok (value.settings, Parameter.no_effects)
                    | changes -> Settings.apply value.settings changes) in
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
               | Ok document -> None, document, effects, edit_error, unchanged)) in
    let timeline_intents = if Workspace.collapsed workspace Workspace.Timeline
      then [] else Pxui.Ui.within ui timeline_root (fun () ->
        Pxui_shell.Timeline_bar.draw ui ~bounds:panes.timeline
          ~playing:(Sketch_support.Timeline.mode timeline = Sketch_support.Timeline.Playing)
          ~frame:(Sketch_support.Timeline.frame timeline)
          ~time:(Sketch_support.Timeline.time timeline)
          ~max_frame:value.timeline_frames) in
    let handle_edits, grab =
      if Workspace.collapsed workspace Workspace.View then [], false
      else Pxui.Ui.within ui view_root (fun () ->
        view_handles ui ~selected ~bounds:panes.view) in
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
    { workspace; focus; pane_keys; graph_view; document; edit_error;
      effects = Parameter.union_effects editor_effects
          (Parameter.union_effects parameter_effects handle_effects);
      timeline_intents; frame_request; prompt = None; prompt_intent = None;
      panel; grab; settings; touched;
      label = (match List.find_map intent_label graph_changes with
        | Some label -> label
        | None when settings != unchanged -> "Settings"
        | None -> (match selected with
          | Some node -> "Edit " ^ Node.label node | None -> "Edit")) } in
  let leader_panel = if leader = Leader.Pending then Some (fun ui ->
    Pxui_shell.Which_key.panel ui keymap ~focus
      ~focus_name:(Leader.pane_name focus)) else None in
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
        (* Every keymap command by label, deduplicated (undo has two chords). *)
        let commands = List.fold_left (fun seen (binding : Leader.binding) ->
            if List.mem_assoc binding.label seen then seen
            else (binding.label, binding.action) :: seen) [] keymap |> List.rev in
        let matches query = List.filter (fun (label, _) ->
            Ui.fuzzy_match ~query label) commands in
        let rows query = Array.of_list (List.map (fun (label, _) -> label, "")
            (matches query)) in
        (match Pxui_shell.Prompt.search ui ~key:"command-palette"
            ~title:"Commands" ~label:"Search commands" ~query ~rows with
         | None | Some (_, `Cancel) -> None, None
         | Some (query, `Pick index) ->
             None, Some (Run_action (snd (List.nth (matches query) index)))
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
      { workspace; focus; pane_keys = []; graph_view; document = value.document;
        edit_error = value.edit_error;
        effects = Parameter.no_effects; timeline_intents = [];
        frame_request = initial_frame_request; prompt = initial_prompt;
        prompt_intent = None; panel = None; grab = false;
        settings = value.settings; touched = false; label = "Edit" } in
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
            ~sketch:value.name ~document:result.document
            ~positions:(Pxui_graph.node_positions result.graph_view)
            ~display:(Some (Pxui_graph.viewed result.graph_view))
            ~active_camera:(Pxui_graph.flagged result.graph_view)
            ~settings:(List.map (fun (field : Parameter.field_view) ->
              field.name, field.current) (Settings.fields result.settings))
            ~view:(view_state result.panel) with
          | Ok path -> "Saved preset " ^ Filename.basename path
          | Error message -> "Preset not saved: " ^ message in
        result.prompt, Some notice, None
    | Some (Load_preset_file name) ->
        (match Preset.load ~path:(Preset.path ~directory:value.presets ~name)
            ~code:value.code_graph ~factories:value.factories with
         | Ok preset -> result.prompt, Some ("Loaded preset " ^ name), Some preset
         | Error message -> result.prompt, Some ("Preset rejected: " ^ message), None)
    | Some (Delete_preset_file { name; query }) ->
        let notice = match Preset.delete ~directory:value.presets ~name with
          | Ok () -> "Deleted preset " ^ name
          | Error message -> "Preset not deleted: " ^ message in
        Some (Browsing { query; presets = Preset.list ~directory:value.presets }),
        Some notice, None in
  let document, graph_view, edit_error, settings = match loaded with
    | None -> result.document, result.graph_view, result.edit_error, result.settings
    | Some (preset : Preset.loaded) ->
        let graph_view = List.fold_left (fun view (node_id, x, y) ->
            Pxui_graph.place_node ~node_id ~x ~y view)
          (Pxui_graph.with_document preset.document graph_view |> Pxui_graph.clear_selection)
          preset.positions in
        let graph_view = match preset.display with
          | Some id -> Pxui_graph.view id graph_view | None -> graph_view in
        let settings, error = match Settings.apply result.settings preset.settings with
          | Ok (settings, _) -> settings, None
          | Error message -> result.settings, Some message in
        preset.document,
        Pxui_graph.with_flagged preset.active_camera graph_view, error, settings in
  (* Shared undo stack: every document change (graph edits, node creation,
     paste, inspector commits) becomes one history entry; Command/Ctrl-Z
     undoes, Shift-Command/Ctrl-Z or Ctrl-Y redoes. *)
  (* ponytail: layout is snapshot whole (O(nodes)) on frames whose graph
     intents or edits changed the document; per-node deltas if graphs grow
     past a few thousand tiles. *)
  let present = Editor_core.History.present value.history in
  let next = if document == present.graph && settings == present.settings
      && not result.touched && Option.is_none loaded then present
    else Document.of_view document graph_view settings in
  let dragging = Frame.mouse_down Input.LeftButton frame in
  let history = if next == present then value.history
    else Editor_core.History.record
        ~label:(if Option.is_some loaded then "Load preset" else result.label)
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
  let history, document, graph_view, settings, undone = match stepped with
    | Some history ->
        let restored = Editor_core.History.present history in
        history, restored.graph, Document.to_view restored graph_view,
        restored.settings, true
    | None -> history, document, graph_view, settings, false in
  let effects = if undone then Parameter.union_effects result.effects Doc.cook_effects
    else result.effects in
  let graph_view = Pxui_graph.with_document document graph_view in
  let displayed_id = Pxui_graph.viewed graph_view in
  let display_changed = displayed_id <> value.displayed_id in
  let document_changed = document != value.document in
  let cooked = Cook.update value.cook ~settings ~document ~displayed_id ~graph:value.graph
      ~displayed_graph:value.displayed_graph ~edit_error ~display_changed
    ~document_changed ~effects ~timeline_changes ~timeline ~frame
    ~frame_request:result.frame_request in
  { core = { value with graph = cooked.graph;
      displayed_graph = cooked.displayed_graph; document; graph_view; displayed_id;
      workspace = result.workspace; timeline; cook = cooked.cook;
      edit_error = cooked.edit_error; settings;
      status_fps; status_fps_at; history; focus = result.focus;
      pane_keys = result.pane_keys; leader; prompt;
      queued = (match result.prompt_intent with Some (Run_action action) -> [action] | _ -> []);
      notice = if document_changed && Option.is_none loaded && not undone then None
        else notice };
    effects; prepared_changed = cooked.prepared_changed;
    framed = cooked.framed;
    loaded_view = Option.map (fun (preset : Preset.loaded) -> preset.view) loaded;
    actions; panel = result.panel;
    input = if not result.grab then frame
      else { frame with mouse_buttons = []; mouse_delta = 0., 0.;
        events = List.filter (function
          | Event.MouseMoved _ | MousePressed _ | MouseReleased _
          | MouseScrolled _ -> false
          | _ -> true) frame.events } }

(* Environment-owned document edits (camera bookkeeping, follow viewport).
   They never affect the displayed cook: [`Reset] starts the history,
   [`Amend] folds into the present entry, and [`View time] coalesces a burst
   of view edits (a drag, a wheel gesture) into one undo entry. *)
let environment_edit value mode document =
  let next = { (Editor_core.History.present value.history) with Document.graph = document } in
  let history = match mode with
    | `Reset -> Editor_core.History.create next
    | `Amend -> Editor_core.History.record ~merge:Repair next value.history
    | `View time -> Editor_core.History.record
        ~merge:(Burst { key = "view"; at = time; window = 0.25 })
        next value.history in
  { value with document; history;
    graph_view = Pxui_graph.with_document document value.graph_view }

let machinery value ~all_ui_visible =
  if all_ui_visible || value.leader = Leader.Pending then Pxui.Ui.scene value.ui
  else []

let close value =
  Pxui.Ui.destroy value.ui;
  Cook.close value.cook

(* A sketch-driven settings change: one undo step and a fresh cook, since
   [prepare] reads the settings. *)
let set_settings value settings =
  if settings == value.settings then value else
  let next = { (Editor_core.History.present value.history) with Document.settings } in
  { value with settings; cook = Cook.force value.cook;
    history = Editor_core.History.record next value.history }
