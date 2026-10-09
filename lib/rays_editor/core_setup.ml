open Rays
open Procedural
open Editor_document
include Core_list

(* ---- creation ---- *)

(* The document a workspace starts from: one geometry object per [sop] graph
   beside the sketch's own scene objects ([seed_scene]). *)
let workspace_doc ~factories ~seed_scene workspace =
  let ( let* ) = Result.bind in
  let flow r = Result.map_error Flow.Diagnostic.to_string r in
  let* doc = flow (Editor_document.Contexts.of_workspace ~factories workspace) in
  let declared = doc.scene.graph.geometry in
  (* the host's camera and lights are defaults of a workspace with no scene graph; a scene
     graph is authoritative (it may say there are none) *)
  let has_scene = Editor_document.Contexts.graph_of workspace Flow.Context.scene <> None in
  let scene = if has_scene then declared else seed_scene declared in
  let* graph = flow (Flow_sop.Network.with_geometry scene doc.scene.graph) in
  let doc = { doc with scene = { doc.scene with graph };
    active_camera = if has_scene then doc.active_camera else List.nth_opt (Objects.ids "camera" scene) 0 } in
  Ok doc

(* A World object for [world], with its layer network. *)
let add_world (doc : Document.t) world =
  let _, values = Layers.of_world world in
  let ( let* ) = Result.bind in
  let* node = Edit_graph.instantiate Layers.Settings.factory [] in
  let* graph = Edit_graph.add_node ~factory:Layers.Settings.factory node doc.scene.graph.geometry in
  let* graph, _ = Edit_graph.apply_parameters graph ~node_id:(Node.id node) values in
  let* network = Layers.network_of_world world in
  Ok { doc with scene = { doc.scene with graph = Result.get_ok (Flow_sop.Network.with_geometry graph doc.scene.graph) };
       networks = Document.Int_map.add (Node.id node) network doc.networks }

(* A new World starts as a daylight sky with a sun, ready to turn. *)
let daylight = Option.value ~default:World.default (List.assoc_opt "daylight" World.presets)

let preferences_file () = match Sys.getenv_opt "RAYS_EDITOR_PREFERENCES" with
  | Some path when path <> "" -> path
  | Some _ | None -> Filename.concat (Filename.concat
      (Option.value ~default:"." (Sys.getenv_opt "HOME")) ".rays") "preferences.rays"

let read_preferences filename =
  Editor_core.Store.Settings.load ~sketch:"rays-editor" filename

let save_guide filename guide =
  let ( let* ) = Result.bind in
  let* values = if Sys.file_exists filename then read_preferences filename else Ok [] in
  Editor_core.Store.Settings.save ~sketch:"rays-editor" filename
    (("guide", Editor_core.Store.Settings.Bool guide) :: List.remove_assoc "guide" values)

let state_directory value = Filename.concat value.presets "state"
let state_file value = Preset.path ~directory:(state_directory value) ~name:value.state_name
let browse value query =
  let last_state = match Unix.stat (state_file value) with
    | { Unix.st_kind = Unix.S_REG; st_mtime; _ } -> Some st_mtime
    | _ | exception Unix.Unix_error _ -> None in
  Some (Browsing { query; presets = Preset.list ~directory:value.presets; last_state })

let create ?settings ?(keymap = Leader.keymap)
    ?(seed_scene = fun _ scene -> scene) ?world
    ?(name = "sketch") ?presets ?(state_key = name) ?(timeline_frames = 240)
    ?(layout = Pxui_shell.Layout.default) ?(factories = [])
    ?(seed = 0L) ?(grain = 16_384)
    ?domains ?(max_entries = 512)
    ?(max_payload_bytes = 256 * 1024 * 1024) ?await ?(carry_budget = 0.5)
    ~workspace ~prepare () =
  let factories = if factories = [] then Sop_catalog.Editor.factories else factories in
  let settings = Option.value settings ~default:workspace.Workspace_doc.settings in
  let opened = workspace_doc ~factories ~seed_scene:(seed_scene factories)
      { workspace with Workspace_doc.settings } in
  Result.bind opened (fun doc ->
  let has_world = Editor_document.Contexts.graph_of workspace Flow.Context.world <> None in
  let doc = match (if Objects.ids "world" doc.scene.graph.geometry = [] && not has_world
                   then Option.map (add_world doc) world else None) with
    | Some (Ok doc) -> doc | Some (Error _) | None -> doc in
  Result.map (fun cook ->
      let workspace = { tree = layout; hidden = [ Pxui_shell.Layout.Timeline ]; live = None; window_live = None;
                        restored = false } in
      let presets = match presets with
        | Some directory -> directory
        | None -> Filename.concat (Filename.concat
            (Option.value ~default:"." (Sys.getenv_opt "HOME")) ".rays")
            (Preset.sanitize name) in
      let level = Document.Scene in
      let preferences = preferences_file () in
      let guide = match read_preferences preferences with
        | Ok values -> Option.value ~default:true (Editor_core.Store.Settings.bool values "guide")
        | Error _ -> true in
      let state_name = Contexts.sha256 state_key in
      let value = { preferences; guide; hud = None; presets; state_name; name; prompt = None; notice = None; notice_at = 0.;
        doc; filed = doc; level;
        projections = Level_map.empty; text = Text_pane.initial; map_view = false;
        rows = []; live_cook = true;
        factories;
        selection = Selection.empty; menu = None;
        scope_view = Pxui_graph.Scope.create (); probes = Layout_by_path.Path_map.empty; lit = None;
        previews = Document.Int_map.empty; viewed = Document.Int_map.empty; canvas_preview = None; canvas_viewed = None; view_key = None;
        scope_key = None; edit_phases = Flow.Phase_timer.empty; select_later = []; open_import = None; pane_graph = None; back = [];
        flow_catalog = lazy (Result.to_option (Editor_document.Contexts.catalog
          ~version:Flow_sop.Manifest.version factories));
        lisp_vocab = lazy (Lisp_text.vocab ~ops:(fst doc.workspace).checked.ops
          (List.map Flow_sop.Catalog.descriptor factories @ Editor_document.Contexts.descriptors));
        tree = Pxui_shell.Tree.create (); outline = Navigator.initial; held_keys = [];
        ui = (let ui = Pxui.Ui.create () in Pxui.Ui.set_font_size ui (default_text_size ()); ui); workspace;
        timeline = Sketch_support.Timeline.create (); live_frame = Frame_input.at_time 0.; cook;
        edit_error = None; status_fps = None;
        status_fps_at = Float.neg_infinity; last_dt = 0.; steady = 0;
        history = Editor_core.History.create doc;
        focus = Editor_core.Panels.main; focus_path = None; pane_keys = []; leader = Leader.Idle;
        keymap; timeline_frames = max 1 timeline_frames; queued = [];
        graph_at = None; graph_pane = None; graph_panes = [];
        list_at = None; text_at = None; outline_at = None; locals = [];
        started = { on = None; views = []; tabs = [] };
        framing = None; carry = None; carry_budget; traces = []; view_tools = None; gates = []; selected_box = None;
        file = (fst doc.Document.workspace).checked.name ^ ".rays" } in
      Cook.set_volatile cook (Flow_sop.Lower.is_volatile (snd doc.workspace));
      (* the panels open as their start keywords say; the first graph pane (the focused leaf, else
         the first) opens on the graph it pins *)
      let on = match Option.bind doc.Document.shell (fun s -> s.start.focus) with
        | Some path -> Some path | None -> None in
      let value = follow_graph value ~focus:(if on = None then value.focus else Pxui_shell.Layout.Graph) ~focus_path:on in
      let value = { value with projections = Option.fold ~none:Level_map.empty ~some:(start_views doc level) (graph_path value) } in
      let value = follow_hosts value ~focus_path:on (panel_hosts value) in
      follow_start value)
    (Cook.create ~prepare ~seed ~grain ?domains ?await ~max_entries
      ~max_payload_bytes ()))
