open Rays
open Procedural
open Editor_document

type bounds = Cook.bounds

(* The panels' text: 13 points, the size of macOS control text (11 is its small size, and the kit
   face is narrow).  [RAYS_UI_FONT_SIZE] overrides it: the tests click the 11-point geometry the
   kit was drawn with.  Command +/-/0 step from it and return to it. *)
let default_text_size () =
  match Option.bind (Sys.getenv_opt "RAYS_UI_FONT_SIZE") int_of_string_opt with
  | Some size when size > 0 -> size
  | _ -> 13
module Level_map = Map.Make (struct
  type t = Document.level
  let compare = Stdlib.compare
end)

(* How the graph pane shows the open network. *)
(* what a message says: information (a dot in its echo tip) or a refusal (the error ink) *)
type notice_kind = Info | Refusal

type projection = Graph_view | List_view | Text_view

(* What the workspace pane was last laid out from: the document, the probes and
   the graph, the recording evaluation of the checked source, and what its
   footers read (the cook's geometry counts, the time of a live document). *)
type scope_key = {
  ws : Workspace_doc.t; probe_map : int Layout_by_path.Path_map.t; graph : string;
  evaluated : Flow.Eval.t option;
  summaries : Cook.summary list; time : float option;
  records : Flow_sop.Probe.t option;
  scope : Flow_sop.Projection.scope;
  targets : (int * int) list;  (* (object, compiled node) the cook is asked to count *)
}

(* What a graph panel keeps of its own while another one has the focus. *)
type graph_pane = {
  view : Pxui_graph.Scope.t; laid : scope_key option; shown : string option;
  route : (Document.level * string option) list; views : projection Level_map.t;
  at : Document.level; picked : Selection.t;  (* its navigation level and that level's selection *)
}

(* What a panel keeps of its own besides its PXUI state while another panel of its kind is the
   one in use: its list, its text pane, its outline (flow.md 11.11). *)
type local = { rows : Pxui_shell.Tree.t; code : Text_pane.state; nav : Navigator.state }

(* The start keywords the editor last followed, by panel key. *)
type started = { on : string list option; views : (string list * string) list;
                 tabs : (string list * string) list }

type prompt =
  | Keys
  | Saving of string
  | Palette of string  (* command search query *)
  | Jumping of string  (* Space j: graph search query *)
  | Browsing of { query : string; presets : (string * float) list; last_state : float option }
  | Making_macro of { nodes : Flow.Workspace.path list; draft : Flow_sop.Flow_edit.macro_draft;
                      state : Pxui_shell.Prompt.macro }  (* the make-macro dialog (plan W9) *)

type prompt_intent = Save_preset_file of string | Load_preset_file of string | Load_last_state
  | Edit_source of Flow_sop.Flow_edit.op  (* the dialog's answer: one workspace gesture *)
  | Delete_preset_file of { name : string; query : string }
  | Delete_last_state of string
  | Run_action of Leader.action
  | Go of string  (* Space j picked a graph *)

type timeline_intent = Pxui_shell.Timeline_bar.intent =
  Pause_toggle | Stop_playback | Reset_playback | Seek_playback of int64 | Set_end of int

(* A traced viewport's readout: the film in pixels, the samples per pixel against their cap, the
   bounces, and the seconds the accumulation has taken (counted from the time [since] its samples
   last restarted, frozen once the cap is reached). *)
type trace = { film : int * int; samples : int; cap : int; bounces : int; seconds : float; since : float }

(* Transient shell presentation: the fallback tree before the first panel edit,
   a splitter draft, and the default-tree override ("Restore layout"). Saved
   disclosure and floating bounds come from the document's layout. *)
type shell = {
  tree : Pxui_shell.Layout.t;
  hidden : Pxui_shell.Layout.panel list;
  live : (Pxui_shell.Layout.path * Editor_core.Panels.size) option;  (* the split being dragged, its size *)
  window_live : (Pxui_shell.Layout.path * Pxui_shell.Layout.bounds) option;
  restored : bool;
}

(* What a pane asks of the document: a gesture on the workspace text, a parameter or the name
   of a scene object or World layer (the inspector), a message. *)
type change =
  | Dock_panels of Pxui_shell.Layout.path * Pxui_shell.Layout.path * [ `Left | `Right | `Top | `Bottom ]
  | Panel_state of Pxui_shell.Layout.path * Editor_core.Panels.state
  | Select_layout of string
  | Syntax_edit of Flow_sop.Flow_edit.op
  | Syntax_batch of string * Flow_sop.Flow_edit.op list
      (** several rewrites that make one gesture (a new SOP graph and its object): all or none,
          one history entry with this label *)
  | Syntax_inline of { home : Document.home; key : Flow_sop.Flow_edit.arg_key;
                       make : Flow.Workspace.path -> Flow_sop.Flow_edit.op }
      (** the expression at [key] of the call at [home] is written in place: the call is bound to
          a name first, then the expression, and [make] gives the gesture on that name (several
          rewrites, one history entry) *)
  | Object_arg of { node : int; key : string; sub : int list; expr : Flow.Syntax.t }
      (** an expression typed in a row of a scene object or World layer: written to the argument of
          the call that holds it (for a loop's copy, of the loop's template) *)
  | Pin_row of { node : Flow.Workspace.path; label : string; pin : bool option }
      (** a row of a node's card pinned onto it or off it ([None]: the default rule), a layout edit *)
  | Notice of string  (** an information message: the echo tip with the dot *)
  | Declined of string  (** a refusal: the echo tip in the error ink *)
  | Set_parameter of { node : int; path : string; value : Parameter.value }
  | Rename of { node : int; label : string }

type 'panel frame_result = {
  workspace : shell;
  focus : Pxui_shell.Layout.panel;
  focus_path : Pxui_shell.Layout.path option;  (* the focused leaf itself, for its panel keys *)
  pane_keys : (int * (Pxui_shell.Layout.panel * Pxui_shell.Layout.path option)) list;
  scope_view : Pxui_graph.Scope.t;
  scope_changes : Pxui_graph.Scope.change list;
  selection : Selection.t;
  menu : Pxui_graph.Node_menu.t option;
  menu_pick : string option;  (* the node menu's entry picked this frame *)
  tree : Pxui_shell.Tree.t;
  outline : Navigator.state;
  outline_intents : Navigator.intent list;
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
  opened : int option;  (* a node asked to be entered *)
  live_cook : bool;
  label : string;  (* names this frame's document change in history *)
  changes : change list;
  tree_intents : Pxui_shell.Tree.intent list;
  text_intents : Text_pane.intent list;
  open_graph : int option;
  settings_changes : (string * Parameter.value) list;
  hide_guide : bool;
  graph_panes : (string list * graph_pane) list;
  locals : (string list * local) list;
  other_texts : (string list * Text_pane.shown * Text_pane.intent list) list;
  (* the text panes that are not the one in use: what each showed and asked this frame *)
  handle_changes : (int * (string * Parameter.value) list) option;
}

(* The tags {!Pick.tint} highlights: those of the merge inputs made by the selected
   node at the current probes.  Cached by what it was computed from. *)
type lit_cache = {
  site : Flow.Workspace.path; at : int Layout_by_path.Path_map.t;
  lowered : Flow_sop.Lower.t; scope : Flow_sop.Projection.scope; tags : Pick.Set.t;
}

(* A carry in flight (carry.ml, flow.md "Carry"): the payload, how it was picked up, the document
   that was the history's present then (the cancel restores it, physically) and what the panes
   saw under the pointer last frame.  While a target is hot the document shown ([doc]) is the edit
   applied to a scratch copy; the history is not touched until the put. *)
type carry_preview =
  | Showing of { place : Carry.place; doc : Document.t; what : string }
  | Held_back of { place : Carry.place; doc : Document.t; what : string; reason : string }
      (* the put would take longer than the preview budget: said, not shown *)
  | Refused of { place : Carry.place; reason : string }

type carry_report = { over : Carry.place; dropped : bool }

type 'prepared carry = {
  payload : Carry.payload;
  via : [ `Pointer | `Keys ];
  original : Document.t;
  settled : 'prepared Cook.piece list;
      (* the pieces cooked for [original]: a surface is picked on them, not on the preview *)
  report : carry_report option;
  targets : (string option * (string * Carry.place * string) list) option;
      (* the key route's letters, computed for the pane graph named *)
  chosen : Carry.place option;  (* the key route's letter *)
  anchor : (float * float) option;
      (* where the pointer was at pick-up or the last letter: it hovers only once it moves *)
  preview : carry_preview option;
  resting : (Carry.place * float) option;  (* the node the pointer rests on, since *)
  hint : string option;  (* a reminder the strip shows ahead of the prompt until a letter is chosen *)
}

type 'prepared t = {
  preferences : string;
  guide : bool;
  hud : (string * float) option;
  presets : string;  (* preset directory *)
  state_name : string;  (* stable sketch identity, separate from named presets *)
  name : string;  (* sketch name recorded in presets *)
  prompt : prompt option;
  notice : (notice_kind * string) option;  (* the last message and what it was: information or a refusal *)
  notice_at : float;  (* when the notice last changed: the echo tip shows it for a while *)
  doc : Document.t;  (* always the history's present *)
  filed : Document.t;  (* the document as its source file has it: an external change may replace it *)
  level : Document.level;
  projections : projection Level_map.t;
  text : Text_pane.state;  (* the workspace text pane: tab, drafts, errors (view state) *)
  map_view : bool;  (* in the World, the view pane shows the lat-long map *)
  live_cook : bool;  (* cook while a drag holds the pointer *)
  rows : (Flow_sop.Network.t * (int option * int option) * (Pxui_shell.Tree.row array * string list)) list;
  (* the rows of the lists drawn last frame, cached by network, display node and active camera *)
  factories : Edit_graph.factory list;  (* the SOP catalog *)
  selection : Selection.t;
  menu : Pxui_graph.Node_menu.t option;  (* the node menu, while it is open *)
  scope_view : Pxui_graph.Scope.t;  (* the workspace document's graph pane *)
  probes : int Layout_by_path.Path_map.t;  (* the iteration each zone shows: view state, not history *)
  lit : lit_cache option;  (* the highlight of the selected node at the probes, see {!lit_tags} *)
  scope_key : scope_key option;
  select_later : Flow.Workspace.path list;  (* nodes to select once the pane shows their graph *)
  pane_graph : string option;  (* a scene, world or settings graph the pane shows instead of the level's own *)
  back : (Document.level * string option) list;  (* where [u] returns to: level and pane graph, latest first *)
  flow_catalog : Flow.Check.catalog option Lazy.t;
  lisp_vocab : Lisp_text.vocab Lazy.t;  (* what the text pane completes and describes *)
  tree : Pxui_shell.Tree.t;
  outline : Navigator.state;  (* the Navigator panel: its search (view state) *)
  ui : Pxui.Ui.t;
  workspace : shell;
  timeline : Sketch_support.Timeline.t;
  cook : 'prepared Cook.t;
  edit_error : string option;
  status_fps : int option;
  status_fps_at : float;
  last_dt : float;  (* the step of the last frame, and how many frames in a row had exactly it: *)
  steady : int;     (* three or more is a fixed step, the timeline header says so *)
  history : Document.t Editor_core.History.t;
  focus : Pxui_shell.Layout.panel;
  focus_path : Pxui_shell.Layout.path option;  (* which leaf of that kind: every leaf is an
    instance, and Space o / Space l act on the one clicked, not the first *)
  pane_keys : (int * (Pxui_shell.Layout.panel * Pxui_shell.Layout.path option)) list;
  leader : Leader.state;
  held_keys : Input.key list;
  keymap : Leader.command list;
  timeline_frames : int;
  queued : Leader.action list;  (* picked in the palette, run next frame *)
  graph_at : Pxui_shell.Layout.path option;  (* where [graph_pane]'s leaf was at the last frame *)
  graph_pane : string list option;
  (* the graph panel that [scope_view], [scope_key], [pane_graph], [back] and [projections] belong
     to, by panel key: the focused one, else the last one focused *)
  graph_panes : (string list * graph_pane) list;  (* the other graph panels' own, by panel key *)
  list_at : string list option;  (* the panel [tree] belongs to: a list panel, or a graph panel in list view *)
  text_at : string list option;  (* the panel [text] belongs to: a lisp panel, or a graph panel in text view *)
  outline_at : string list option;  (* the panel [outline] belongs to *)
  locals : (string list * local) list;  (* the other panels' own, by panel key *)
  started : started;
  carry : 'prepared carry option;
  carry_budget : float;  (* seconds a carry's preview may take to apply or cook before it is only described *)
  captions : (string * string) list;
  traces : (string * trace) list;  (* what each traced viewport's readout says: the film, the samples, the bounces and the seconds the accumulation took *)
  file : string;  (* what the status strip calls the document: its source file, else its name *)
  gates : (string * (int * int * int * int)) list;  (* the render frame of each viewport that shows less than its pane *)
  selected_box : (string * (int * int * int * int) * string) option;  (* the selected object in the focused view: its screen box and name *)
  view_tools : (bool * int) option;  (* the active viewport's header: looking through, and its renderer (0 solid, 1 wire, 2 traced); none for a 2D view *)
  (* each traced viewport's header text (resolution, film step, samples), set by the host after
     it renders: view state, not history *)
}

type ('prepared, 'panel) update = {
  core : 'prepared t;
  effects : Parameter.effects;
  prepared_changed : bool;
  scene_changed : bool;  (* objects, lights, or the World changed: recompose *)
  framed : bounds option option;
  (** A framing request finished: [Some None] had no geometry. *)
  loaded_view : Flow.Syntax.t option;
  (** A preset loaded this frame; its environment view settings. *)
  actions : Leader.action list;
  panel : 'panel option;
  (* The frame without leader-consumed events, for the environment's own
     input handling. *)
  input : Frame.t;
}

(* ---- the shell ---- *)

(* The layouts Space [ switches among: a switch's, named from their panels; else the editor graphs of an
   older file (several named layouts), the current one marked. *)
let layouts value =
  match value.doc.Document.shell with
  | Some { switch = Some sw; _ } ->
      List.mapi (fun i name -> name, i = sw.active) (Editor_core.Panels.labels sw.layouts)
  | _ ->
      let doc = fst value.doc.Document.workspace in
      let current = Option.map (fun (g : Flow.Workspace.graph) -> g.name) (Workspace_doc.editor_graph doc) in
      (match List.filter (fun (g : Flow.Workspace.graph) -> g.context = Flow.Workspace.Editor) doc.checked.graphs with
       | [] | [ _ ] -> []
       | gs -> List.map (fun (g : Flow.Workspace.graph) -> g.name, Some g.name = current) gs)

(* What the text pane completes beyond its own text: the graphs, the materials, the cameras of the
   first scene graph and the layouts. *)
let completion_names value : Lisp_text.names =
  let ws = fst value.doc.Document.workspace in
  let graphs = ws.checked.graphs in
  let named context = List.filter_map (fun (g : Flow.Workspace.graph) ->
    if g.context = context then Some g.name else None) graphs in
  { graphs = List.map (fun (g : Flow.Workspace.graph) -> g.name) graphs;
    materials = named Flow.Workspace.Material;
    cameras = (match named Flow.Workspace.Scene with
      | scene :: _ -> Text_pane.cameras ws.source scene | [] -> []);
    layouts = List.map fst (layouts value) }

(* The tree drawn now: the editor graph's (the host's when the document has none, or
   after "Restore layout"), with the split being dragged at its live ratio. *)
let shell_tree value (shell : shell) =
  let base = if shell.restored then shell.tree
    else match value.doc.Document.shell with Some s -> s.tree | None -> shell.tree in
  match shell.live with
  | Some (node, size) -> Editor_core.Panels.set_size node size base
  | None -> base

let visible (shell : shell) panel = not (List.mem panel shell.hidden)

let panel_key (doc : Document.t) path =
  let graph = Option.fold ~none:"@default" ~some:(fun (g : Flow.Workspace.graph) -> g.name)
    (Workspace_doc.editor_graph (fst doc.workspace)) in
  let origin path = Option.bind doc.shell (fun s -> List.assoc_opt path s.Document.origins) in
  let rec node path (tree : Editor_core.Panels.t) = match path, tree with
    | [], tree -> Some tree
    | 0 :: rest, Split s -> node rest s.a
    | 1 :: rest, Split s -> node rest s.b
    | i :: rest, Tile cells -> Option.bind (List.nth_opt cells i) (node rest)
    | 0 :: rest, Float t -> node rest t
    | _ -> None in
  (* a binding several leaves are made from names none of them: each is keyed by its place *)
  let once name = not (Option.fold ~none:false ~some:(fun (s : Document.shell) -> List.mem name s.repeated) doc.shell) in
  match origin path, List.rev path with
  | Some (Document.Bound name), _ when once name -> [graph; name]
  (* [name (ui/floating (ui/inspector))]: the window is the float's binding *)
  | _, 0 :: up when (match Option.bind doc.shell (fun s -> node (List.rev up) s.tree), origin (List.rev up) with
      | Some (Float _), Some (Document.Bound _) -> true | _ -> false) ->
      (match origin (List.rev up) with Some (Document.Bound name) -> [graph; name] | _ -> assert false)
  | _ -> graph :: "@panel" :: List.map string_of_int path

let panel_state value path =
  let saved key = Layout_by_path.Path_map.find_opt key (fst value.doc.workspace).layout.panels in
  let state = if value.workspace.restored then Editor_core.Panels.default_state else
    match saved (panel_key value.doc path) with
    | Some state -> state
    | None ->
        (* a leaf of a binding used twice starts from the binding's entry (flow.md 11.11) *)
        let by_name = match Option.bind value.doc.shell (fun s -> List.assoc_opt path s.Document.origins),
                            panel_key value.doc path with
          | Some (Document.Bound name), graph :: "@panel" :: _ -> saved [ graph; name ]
          | _ -> None in
        Option.value by_name ~default:{ Editor_core.Panels.default_state with collapsed = path = [-1] } in
  match value.workspace.window_live with
  | Some (p, window) when p = path -> { state with window = Some window }
  | _ -> state

(* An edit that changes the editor graph's tree ends "Restore layout". *)
let unrestore (before : Document.t) (after : Document.t) (shell : shell) =
  let tree (doc : Document.t) = Option.map (fun (s : Document.shell) -> s.tree) doc.shell in
  if tree before <> tree after then { shell with restored = false; window_live = None } else shell
(* the host bar above the panels: a document with an editor graph has one *)
let shell_hidden value (shell : shell) =
  if shell.restored then shell.hidden else
  if (panel_state value [-1]).collapsed
    && not (List.exists (fun (_, p) -> p = Pxui_shell.Layout.Timeline)
      (Editor_core.Panels.leaves (shell_tree value shell)))
  then [Pxui_shell.Layout.Timeline] else []
let geometry value (shell : shell) frame =
  Pxui_shell.Layout.geometry ~state:(panel_state value) ~hidden:(shell_hidden value shell) (shell_tree value shell) frame
let has_panel value panel =
  visible value.workspace panel
  && List.exists (fun (path, p) -> p = panel && not (panel_state value path).collapsed)
    (Editor_core.Panels.leaves (shell_tree value value.workspace))

(* The viewport that keyboard focus and the camera follow: the focused one, else the first. *)
let active_view value (g : Pxui_shell.Layout.geometry) = match value.focus with
  | View _ as panel when Pxui_shell.Layout.find g panel <> None -> Pxui_shell.Layout.find g panel
  | _ -> Pxui_shell.Layout.first_view g

let panes value frame =
  let g = geometry value value.workspace frame in
  let panes = Pxui_shell.Layout.panes g in
  match active_view value g with
  | Some leaf -> { panes with view = leaf.body }
  | None -> panes

(* The viewports on screen and the bodies they are drawn in. *)
let view_bodies value frame =
  List.filter_map (fun (leaf : Pxui_shell.Layout.leaf) -> match leaf.panel with
    | View key when not (panel_state value leaf.path).collapsed -> Some (key, leaf.body) | _ -> None)
    (geometry value value.workspace frame).leaves

let view_visible value =
  List.exists (fun (path, p) -> match p with Pxui_shell.Layout.View _ ->
    visible value.workspace p && not (panel_state value path).collapsed | _ -> false)
    (Editor_core.Panels.leaves (shell_tree value value.workspace))

(* ---- graph panels: each [ui/graph] leaf is a pane of its own ---- *)

(* The graph leaves of the tree shown, by panel key: walked once a frame ([follow_graph]). *)
let graph_leaves value =
  List.filter_map (fun (path, p) ->
    if p = Pxui_shell.Layout.Graph then Some (panel_key value.doc path, path) else None)
    (Editor_core.Panels.leaves (shell_tree value value.workspace))

(* The leaf of the pane in use: where [graph_pane] was last seen when that is still its leaf (no
   walk: this is read many times a frame), else found again, else the first graph leaf. *)
let graph_path value =
  let rec panel path (tree : Editor_core.Panels.t) = match path, tree with
    | [], Leaf p -> Some p
    | 0 :: rest, Split s -> panel rest s.a
    | 1 :: rest, Split s -> panel rest s.b
    | i :: rest, Tile cells -> Option.bind (List.nth_opt cells i) (panel rest)
    | 0 :: rest, Float t -> panel rest t
    | _ -> None in
  match value.graph_pane, value.graph_at with
  | Some key, Some path when panel path (shell_tree value value.workspace) = Some Pxui_shell.Layout.Graph
                             && panel_key value.doc path = key -> Some path
  | _ ->
      let leaves = graph_leaves value in
      (match Option.bind value.graph_pane (fun key -> List.assoc_opt key leaves), leaves with
       | Some path, _ -> Some path
       | None, (_, path) :: _ -> Some path
       | None, [] -> None)

(* What a graph leaf's own keywords open it with: its [:view], else the canvas when it pins a graph. *)
let start_views (doc : Document.t) level path =
  match doc.shell with
  | None -> Level_map.empty
  | Some s ->
      (match List.assoc_opt path s.start.graph_views with
       | Some "list" -> Level_map.singleton level List_view
       | Some "text" -> Level_map.singleton level Text_view
       | Some _ -> Level_map.singleton level Graph_view
       | None -> if List.mem_assoc path s.named then Level_map.singleton level Graph_view else Level_map.empty)

let stash value = { view = value.scope_view; laid = value.scope_key; shown = value.pane_graph;
                    route = value.back; views = value.projections; at = value.level; picked = value.selection }

(* The editor as the graph panel [key] at [path] has it: its own pane when it is not the one in use.
   The document may have changed under a pane that waited (an undo from another panel): its level
   is resolved again, and a level that is gone takes its selection with it. *)
let as_pane value (key, path) =
  if value.graph_pane = Some key then value else
  let pane = match List.assoc_opt key value.graph_panes with
    | Some pane -> pane
    | None -> { view = Pxui_graph.Scope.create (); laid = None; shown = None; route = [];
                views = start_views value.doc value.level path; at = value.level; picked = Selection.empty } in
  let level = Document.resolve_level value.doc pane.at in
  { value with graph_pane = Some key; graph_at = Some path; scope_view = pane.view; scope_key = pane.laid;
               pane_graph = pane.shown; back = pane.route; projections = pane.views;
               level; selection = if level = pane.at then pane.picked else Selection.empty }

(* The graph leaf an inspector, list or lisp leaf is tied to by [:of]. *)
let tied value path =
  if value.workspace.restored then None else
  Option.bind value.doc.Document.shell (fun s ->
    Option.map (fun target -> panel_key value.doc target, target) (List.assoc_opt path s.follows))

(* The pane in use follows the focus: the focused graph leaf, else the one it was, else the first
   one open.  The pane left keeps its canvas, selection, graph and route. *)
let follow_graph value ~focus ~focus_path =
  let all = graph_leaves value in
  let value = { value with graph_at = Option.bind value.graph_pane (fun key -> List.assoc_opt key all) } in
  let leaves = List.filter (fun (_, path) -> not (panel_state value path).collapsed) all in
  (* the focused graph leaf, or the one the focused leaf is tied to: its edits land there *)
  let focused = Option.bind focus_path (fun path ->
    let path = if focus = Pxui_shell.Layout.Graph then Some path else Option.map snd (tied value path) in
    Option.bind path (fun path -> List.find_opt (fun (_, p) -> p = path) leaves)) in
  let target = match focused, value.graph_pane with
    | Some leaf, _ -> Some leaf
    | None, Some key when List.mem_assoc key leaves -> None
    | None, _ -> List.nth_opt leaves 0 in
  match target, value.graph_pane with
  | None, _ -> value
  | Some (key, _), Some current when key = current -> value
  | Some (key, path), None ->  (* the first pane: the state so far is its *)
      { value with graph_pane = Some key; graph_at = Some path }
  | Some leaf, Some current ->
      let left = (current, stash value) :: List.remove_assoc current value.graph_panes in
      let value = as_pane { value with graph_pane = None; graph_panes = left } leaf in
      { value with graph_panes = List.filter (fun (key, _) -> List.mem_assoc key all
                                                              && Some key <> value.graph_pane) left }

let pane_ui bounds =
  let x, y, width, height = bounds in
  x + 8, y + 8, max 1 (width - 16), max 40 (height - 16)

(* The inspector column's kit panel. *)
(* A window is the input sheet: its panes paint their ground with the theme's panel colour, so
   they are built with the sheet as that colour. *)
let sheet_theme (theme : Pxui.Theme.t) =
  { theme with panel = theme.input; ink_ground = Some (Option.value theme.ink_ground ~default:theme.panel) }
let on_sheet ui floating build =
  if not floating then build () else begin
    let theme = Pxui.Ui.theme ui in
    Pxui.Ui.set_theme ui (sheet_theme theme);
    Fun.protect ~finally:(fun () -> Pxui.Ui.set_theme ui theme) build
  end

let inspector_panel ?window ui bounds build =
  let x, y, width, height = bounds in
  Pxui.Ui.panel ?window ui ~x:(float_of_int x) ~y:(float_of_int y)
    ~width:(float_of_int width) ~height:(float_of_int height)
    ~padding:0 "workspace-inspector-panel" build

(* The inspector rows of a scene object or a World layer: its fields, a vec3 in one row. *)
let object_rows ?(locked = false) fields =
  Result.map (List.map (fun (parameter : Flow_sop.Port.parameter) ->
    { Pxui_shell.Inspector.path = parameter.path; fields = parameter.fields; shown = false;
      locked; drive = None; live = None; components = [];
      split = if parameter.ty = Some Flow.Port_type.Vec3 then Some false else None }))
    (Flow_sop.Port.parameters (Editor_document.Contexts.group_triples fields))

(* ---- levels ---- *)

let scene value = Document.scene_graph value.doc

(* Membership is shared by drawing, lighting, picking and framing. *)
let view_wants value view id =
  let views = match value.doc.Document.shell with Some s -> s.views | None -> [] in
  match view with
    | `All -> true
    | `Primary -> not (List.exists (fun (_, ids) -> List.mem id ids) views)
    | `Only key -> (match List.assoc_opt key views with Some ids -> List.mem id ids | None -> false)

let kind value id = Option.map Node.operation (Edit_graph.find (scene value) ~node_id:id)

let level_key = function
  | Document.Scene -> "scene"
  | Inside id -> "object:" ^ string_of_int id

(* The kinds the node menu offers where the pane shows a graph of [context]. *)
let catalog value = function
  | Flow.Workspace.Scene -> Objects.catalog
  | World -> Layers.catalog
  | _ -> value.factories

(* the open level's network; the scene's if the level is gone (every path resolves the level first) *)
let network value =
  Option.value ~default:value.doc.Document.scene (Document.network value.doc value.level)
let document value = (network value).graph.geometry

(* A named pane or Navigator can show a SOP graph while the scene list is open. Its
   compiled nodes belong to an object's network, independent of the list's level. *)
let node_owner value node_id =
  let owns (network : Document.network) = Edit_graph.find network.graph.geometry ~node_id <> None in
  match value.level with
  | Inside id when Option.fold ~none:false ~some:owns (Document.Int_map.find_opt id value.doc.networks) -> Some id
  | _ ->
      (* ponytail: scan owners on this fallback; add an ownership index if large scenes need it. *)
      Document.Int_map.fold (fun id network found ->
        match found with Some _ -> found | None -> if owns network then Some id else None)
        value.doc.networks None

let compiled_node value node_id =
  let owned = Option.bind (node_owner value node_id) (fun id ->
    let graph = match Cook.applied value.cook id with
      | Some resolved -> resolved.Flow_sop.Value_lane.geometry
      | None -> (Document.Int_map.find id value.doc.networks).graph.geometry in
    Edit_graph.find graph ~node_id) in
  match owned with
  | Some _ -> owned
  | None -> List.find_map (fun (g : Flow_sop.Lower.graph) -> Edit_graph.find g.network.geometry ~node_id)
      (snd value.doc.workspace).graphs

(* A new material graph: a free name and its Set_graph ([Material] in the add menu, "new material"
   in the inspector). *)
let new_material value =
  let ws, _ = value.doc.Document.workspace in
  let taken n = List.exists (fun (g : Flow.Workspace.graph) -> g.name = n) (ws.checked.graphs @ ws.checked.defs) in
  let rec pick i = let n = if i = 1 then "material" else "material_" ^ string_of_int i in
    if taken n then pick (i + 1) else n in
  let name = pick 1 in
  match Flow.Syntax.parse (Printf.sprintf
      "(graph %s :context material (material/standard :name \"%s\" :color \"#cccccc\" :roughness 0.4))" name name) with
  | Ok [ form ] -> name, Flow_sop.Flow_edit.Set_graph { name; form }
  | _ -> failwith "new_material"

(* "=(* 2 t)" typed in a row: the expression after the "=", any Lisp expression *)
let expression_text text =
  match Flow.Syntax.parse (String.sub text 1 (String.length text - 1)) with
  | Ok [ expr ] -> Ok expr
  | Ok _ -> Error "Write one expression after the ="
  | Error d -> Error ("Expression: " ^ d.Flow.Diagnostic.message)

(* 1204 as "1 204" *)
let group_digits n =
  let text = string_of_int (abs n) in
  let len = String.length text in
  let b = Buffer.create (len + 4) in
  if n < 0 then Buffer.add_char b '-';
  String.iteri (fun i c -> if i > 0 && (len - i) mod 3 = 0 then Buffer.add_char b ' '; Buffer.add_char b c) text;
  Buffer.contents b

(* the section of a kind's arguments that have no folder: its own name ("sop/copy_to_points" is Copy to points) *)
let kind_label head =
  let leaf = match String.rindex_opt head '/' with
    | Some i -> String.sub head (i + 1) (String.length head - i - 1) | None -> head in
  String.capitalize_ascii (String.map (fun c -> if c = '_' then ' ' else c) leaf)

(* The arguments of a kind the editor has no compiled node for (a scene or material node), as the
   fields a node would give: the checked kind's parameters, valued by what is written in [authored]. *)
let kind_fields value graph head authored =
  let module S = Flow.Syntax in
  let ws, _ = value.doc.Document.workspace in
  let context = Option.bind (List.find_opt (fun (g : Flow.Workspace.graph) -> g.name = graph)
      (ws.checked.graphs @ ws.checked.defs)) (fun (g : Flow.Workspace.graph) -> match g.context with
    | Flow.Workspace.Sop -> Some Flow.Context.Sop | Scene -> Some Flow.Context.Scene
    | World -> Some Flow.Context.World | Settings -> Some Flow.Context.Settings
    | Material -> Some Flow.Context.Material | _ -> None) in
  match Lazy.force value.flow_catalog, context with
  | _ when head = "material/standard" ->
      (* a built-in of the workspace, not a catalog kind: its four keywords *)
      let number (e : S.t) = match e.node with S.Num t -> float_of_string_opt t | _ -> None in
      let field name default view =
        let current = match authored name, default with
          | Some { S.node = S.Str t; _ }, Parameter.Text_value _ -> Parameter.Text_value t
          | Some e, Parameter.Float_value _ -> (match number e with Some f -> Parameter.Float_value f | None -> default)
          | _ -> default in
        { Parameter.name; label = name; description = None; folder = []; impact = Parameter.Cook; primary = false;
          unit = None; vec3 = None; kind = view; default; current } in
      Some [ field "name" (Parameter.Text_value "") Parameter.Text_view;
             field "color" (Parameter.Text_value "#cccccc") Parameter.Text_view;
             field "roughness" (Parameter.Float_value 0.5)
               (Parameter.Floating_view { soft_min = 0.; soft_max = 1.; hard_min = Some 0.; hard_max = Some 1. });
             field "emission" (Parameter.Text_value "#000000") Parameter.Text_view ]
  | Some catalog, Some context ->
      (match Flow.Check.resolve_kind catalog context head with
       | Error _ -> None
       | Ok (k : Flow.Check.kind) ->
           let number (e : S.t) = match e.node with S.Num t -> float_of_string_opt t | _ -> None in
           (* the render settings an old camera carried are shown only while a file still writes them *)
           let legacy (p : Flow.Check.parameter) = head = "scene/camera" && authored p.name = None
             && List.mem p.name [ "width"; "height"; "max_spp" ] in
           Some (List.concat_map (fun (p : Flow.Check.parameter) ->
             if legacy p then [] else
             let written = authored p.name in
             let three = List.length p.fields = 3 && p.ty = Some Flow.Port_type.Vec3 in
             List.mapi (fun i (name, view, default) ->
               let current = match written, default with
                 | Some { S.node = S.Vec [ a; b; c ]; _ }, Parameter.Float_value _ when three ->
                     (match number (List.nth [ a; b; c ] i) with Some f -> Parameter.Float_value f | None -> default)
                 | Some e, Parameter.Float_value _ when not three ->
                     (match number e with Some f -> Parameter.Float_value f | None -> default)
                 | Some { S.node = S.Num t; _ }, Parameter.Int_value _ ->
                     (match int_of_string_opt t with Some n -> Parameter.Int_value n | None -> default)
                 | Some { S.node = S.Str t; _ }, Parameter.Choice_value _ -> Parameter.Choice_value t
                 | Some { S.node = S.Str t; _ }, Parameter.Text_value _ -> Parameter.Text_value t
                 | Some { S.node = S.Sym ("true" | "false" as b); _ }, Parameter.Bool_value _ ->
                     Parameter.Bool_value (b = "true")
                 | _ -> default in
               { Parameter.name; label = (if three then name else p.label); description = None; folder = p.folder;
                 impact = Parameter.Cook; primary = false; unit = (if three then None else p.unit);
                 vec3 = (if three then Some (p.name, i) else None); kind = view; default; current })
               p.fields) k.parameters))
  | _ -> None

(* The inspector of the node selected in the workspace pane (plan W5): its
   value at the probe, whether it recooks every frame, the list of its
   iterations (a click moves the zone's probe), and the catalog parameters of
   the lowered node at that iteration.  An edit is a [Set_arg] on the authored
   argument; an argument that is not a literal shows its expression and is
   locked.  Returns the graph requests and the probe moves. *)
let workspace_inspector ?(window = false) ?(on_choice = fun _ _ -> ()) ?(resized = fun _ _ -> None) ?(follows = fun _ -> None) value ui ~width path =
  let module P = Flow_sop.Projection in
  let module Probe = Flow_sop.Probe in
  let module S = Flow.Syntax in
  match value.scope_key, value.doc.Document.workspace with
  | Some { scope; records = Some records; graph; _ }, (_, lowered) ->
      (match P.find scope path with
       | None ->
           (* a graph input: its type, and its default as one Lisp form (the pane's field, here) *)
           (match List.find_opt (fun (i : P.input) -> i.path = path) scope.inputs with
            | None -> [], []
            | Some input ->
                ignore (Pxui.Ui.inspector_header ui ~key:"ws-input" ~kind:"input" ~title:input.name
                  ~detail:(Flow.Ty.to_string input.ty) ());
                let shown = match input.default with Some d -> Flow.Lisp.flat d | None -> "" in
                let text = Pxui.Ui.inspector_body ui (fun () ->
                  let box, cx, cy, cw = Pxui.Ui.inspector_row ui ~width ~key:"ws-input-default" ~label:"default" () in
                  Pxui.Ui.within ui box (fun () ->
                    match input.default with
                    | Some { S.node = S.Num _; _ } ->
                        (* a number: the pane's own field, so it drags here as it does on the card *)
                        Option.value ~default:shown
                          (Pxui_graph.Scope.num_field ui ~at:(cx, cy) ~w:cw ~h:20. "ws-input-default-field" shown)
                    | _ ->
                        fst (Pxui.Ui.value_field ui ~at:(cx, cy) ~w:cw ~h:20.
                          ~left:(float_of_string_opt shown = None)
                          ~valid:(fun t -> String.trim t <> "") "ws-input-default-field" shown))) in
                (match (if text = shown then Ok [] else Flow.Syntax.parse text) with
                 | Ok [ form ] ->
                     [ Syntax_edit (Flow_sop.Flow_edit.Set_input_default { form = graph; input = input.name; value = form }) ], []
                 | Ok [] -> [], []
                 | Ok _ -> [ Declined "A default is one Lisp form" ], []
                 | Error d -> [ Declined ("Default: " ^ d.Flow.Diagnostic.message) ], []))
       | Some n ->
           let probe p = Option.value ~default:0 (Layout_by_path.Path_map.find_opt p value.probes) in
           let chain = Option.value ~default:[] (Hashtbl.find_opt (Probe.chains scope) n.path) in
           let probes = List.map probe chain in
           let footer = Probe.footer records n ~probes in
           (* a loop or scope says what it is, then the rows of its rail (what it runs over, what it feeds back,
              what it only reads), as the study's inspector does *)
           let zone_text = Option.map (fun (z : P.zone) -> match z.kind with
             | P.For -> "repeat · collect a list", Printf.sprintf "Runs its body once for every %s and collects the results into a list."
             | Fold -> "iterate · feed back", Printf.sprintf "Runs its body for every %s and hands the result to the next run."
             | Scan -> "scan · keep every step", Printf.sprintf "Runs its body for every %s and keeps each step's result in a list."
             | Sum -> "sum · add up", Printf.sprintf "Runs its body for every %s and adds the results."
             | Let -> "scope · names for its result", (fun _ -> "Names shared by its result; it runs once.")
             | Fn -> "function · runs per call", (fun _ -> "A function: its body runs each time it is called.")) n.zone in
           (* a bypassed node passes its input through: the plan node is the upstream one, so it
              has no number, cook or arguments of its own to show here *)
           let node_id = if n.bypass then None else Option.bind (Probe.plan_node records n.path ~probes) (fun id ->
             Flow_sop.Network.Int_map.find_opt id lowered.compiled) in
           let node = Option.bind node_id (compiled_node value) in
           let literal = function
             | { S.node = S.Num _ | S.Str _ | S.Sym ("true" | "false"); _ } -> true
             | { S.node = S.Vec l; _ } -> List.for_all (fun (e : S.t) -> match e.node with S.Num _ -> true | _ -> false) l
             | _ -> false in
           let authored_row key =
             Option.bind (List.find_opt (fun (r : P.row) -> r.key = Flow_sop.Flow_edit.Kw key) n.rows)
               (fun (r : P.row) -> r.expr) in
           let authored (parameter : Flow_sop.Port.parameter) = authored_row parameter.path in
           (* the arguments: a compiled node's own fields, else (a scene or material node, which
              has none) the checked kind's parameters, valued by what is written *)
           let fields = match node with
             | Some node -> Node.parameter_fields node
             | None -> Option.value ~default:[] (kind_fields value graph n.head authored_row) in
           let parameters = Result.value ~default:[] (Flow_sop.Port.parameters fields) in
           (* the docked column under ~340 points (workspace.html) has no number and no bar; the
              window follows windows.html (no bar); the 380 column (inspector.html) has both *)
           let narrow = width < 340. in
           let doc_layout = (fst value.doc.Document.workspace).layout in
           let pin_of (r : P.row) = Option.bind (Layout_by_path.Path_map.find_opt n.path doc_layout.rows)
             (Layout_by_path.String_map.find_opt r.label) in
           let row_of path = List.find_opt (fun (r : P.row) -> r.key = Flow_sop.Flow_edit.Kw path) n.rows in
           let on_card_row path = match row_of path with
             | Some r -> P.row_shown ?pin:(pin_of r) r | None -> false in
           let geo = Option.bind node_id (fun id -> Option.bind (node_owner value id) (fun object_id ->
             Cook.geometry value.cook ~object_id ~node_id:id)) in
           (* the node shown in the viewport: the graph's recorded display, else its result *)
           let displayed = match Layout_by_path.Path_map.find_opt [ graph ] (fst value.doc.Document.workspace).layout.display with
             | Some p -> Some p
             | None -> (match scope.result with
                 | P.Link target -> Some [ graph; target ]
                 | Node p -> Some p
                 | Literal _ -> None) in
           let readouts = Probe.readouts records n ~probes in
           (* the head: the kind, VIEW while displayed, the node's number; the name edited in
              place; what the probe and the cook know; the flags the card has as buttons *)
           let follow = follows n.path in
           (* the active camera: the one the scene's root names as its :camera *)
           let root_node = List.find_opt (fun (m : P.node) -> m.head = "scene/root") scope.nodes in
           let active_camera = n.head = "scene/camera" && (match root_node with
             | Some root -> List.exists (fun (r : P.row) -> r.key = Flow_sop.Flow_edit.Kw "camera" && (match r.expr with
                 | Some { S.node = S.Sym name; _ } -> name = List.nth n.path (List.length n.path - 1)
                 | _ -> false)) root.rows
             | None -> false) in
           (* a scene or material node says its state: the active camera is `active`, the rest how it cooks *)
           let scene_state = if not (String.starts_with ~prefix:"scene/" n.head || String.starts_with ~prefix:"material/" n.head)
             then None else Some (if active_camera then "active" else
               Option.value ~default:"cached" (List.assoc_opt "cook" readouts)) in
           let buttons =
             (if n.ty = Flow.Ty.Geometry && List.length n.path = 2 && not n.synthetic then
                [ { Pxui.Ui.caption = "View"; keycap = "V"; active = displayed = Some n.path; usable = true }, `View ]
              else [])
             @ (if P.bypassable n then
                  [ { Pxui.Ui.caption = "Bypass"; keycap = "B"; active = n.bypass; usable = true }, `Bypass ] else [])
             @ (match root_node with
                | Some root when n.head = "scene/camera" ->
                    [ { Pxui.Ui.caption = "Active"; keycap = ""; active = active_camera; usable = not active_camera },
                      `Activate root.path ]
                | _ -> [])
             @ (if follow <> None then
                  [ { Pxui.Ui.caption = "Enter"; keycap = "I"; active = false; usable = true }, `Enter ] else []) in
           let head = Pxui.Ui.inspector_header ui ~key:"ws-header" ~kind:n.head
             ?badge:(if displayed = Some n.path then Some "view" else None)
             ?index:(if narrow || window then None else Option.map (Printf.sprintf "NO. %04d") node_id)
             ?rename:(if n.synthetic then None else Some Flow.Symbol.valid_name)
             ~actions:(List.map fst buttons)
             ~title:(Flow_sop.Projection.title n)
             ~detail:(match zone_text with
               | Some (kind, _) -> Printf.sprintf "%s · %s" kind (Flow.Ty.to_string n.ty)
               | None ->
                   (match geo with
                    | Some g ->
                        (* what the cook knows of the node: its points and primitives *)
                        let count k word = Printf.sprintf "%s %s" (group_digits k) word in
                        String.concat " · " ([ count g.points (if g.points = 1 then "point" else "points");
                          count g.prims (if g.prims = 1 then "prim" else "prims") ]
                          @ Option.to_list (Option.map (Printf.sprintf "cooked %.3f s") g.seconds))
                    | None ->
                   (match scene_state with
                    | Some state -> n.head ^ " · " ^ state
                    | None ->
                   (match String.concat " · " (List.map snd readouts) with
                    | "" -> Flow.Ty.to_string n.ty | text -> text)))) ~reset:"Reset all" ~reset_enabled:(List.exists (fun (parameter : Flow_sop.Port.parameter) -> authored parameter <> None) parameters) () in
           let pressed = Option.map (fun i -> snd (List.nth buttons i)) head.chosen in
           (* Reset all: every written argument of the node removed, one undoable entry *)
           let reset_all = if not head.reset_pressed then [] else
             match List.filter_map (fun (parameter : Flow_sop.Port.parameter) ->
               Option.map (fun _ -> Flow_sop.Flow_edit.Disconnect { node = n.path;
                 key = Flow_sop.Flow_edit.Kw parameter.path; fallback = None }) (authored parameter)) parameters with
             | [] -> []
             | [ op ] -> [ Syntax_edit op ]
             | ops -> [ Syntax_batch ("Reset all", ops) ] in
           (* the name: editing it is the pane's Rename (the text's binding name); a nested node
              has no name yet, giving it one binds it *)
           let rename = if n.synthetic || head.renamed = Flow_sop.Projection.title n then []
             else [ Syntax_edit (Flow_sop.Flow_edit.Rename { node = n.path; to_ = head.renamed }) ] in
           let flags = match pressed with
             | Some `Bypass -> [ Syntax_edit (Flow_sop.Flow_edit.Toggle_bypass { node = n.path }) ], []
             | Some `View -> [], [ Pxui_graph.Scope.Display_set n.path ]
             | Some `Enter -> [], [ Pxui_graph.Scope.Activated n.path ]
             | Some (`Activate root) ->
                 [ Syntax_edit (Flow_sop.Flow_edit.Set_arg { node = root; key = Flow_sop.Flow_edit.Kw "camera"; sub = [];
                     value = S.make (S.Sym (List.nth n.path (List.length n.path - 1))) }) ], []
             | None -> [], [] in
           let on_card = ref 0 in
           let requests, picks = Pxui.Ui.inspector_body ui (fun () ->
           (match n.zone, zone_text with
            | Some z, Some (_, sentence) ->
                let vars = List.filter_map (fun (r : P.rail_row) -> if r.role = P.Var then Some r.name else None) z.rail in
                Pxui.Ui.inspector_message ui ~key:"ws-zone-says"
                  (sentence (match vars with v :: _ -> v | [] -> "item"));
                List.iter (fun (r : P.rail_row) ->
                  let label = match r.role with P.Var -> r.name ^ " in" | Acc -> r.name ^ " (next)"
                    | Param -> r.name ^ " (input)" | Capture -> r.name in
                  Pxui.Ui.inspector_readout ui ~width ~key:("ws-rail-" ^ r.name) ~label
                    (match r.expr with Some e -> Flow.Lisp.flat e | None -> "same for all")) z.rail
            | _ -> ());
           (* the head's detail line says it for a node; a zone keeps its readout rows *)
           if zone_text <> None then
             List.iter (fun (label, text) ->
               Pxui.Ui.inspector_readout ui ~width ~key:("ws-" ^ label) ~label text) readouts;
           let hoist = if footer.invariant && Pxui.Ui.inspector_button ui ~key:"ws-hoist" "Move out of the loop"
             then [ Syntax_edit (Flow_sop.Flow_edit.Hoist { node = n.path }) ] else [] in
           (* a macro call: what it is, and the request the pane's lens button makes *)
           let macro = match n.macro with
             | Some name ->
                 Pxui.Ui.inspector_message ui ~key:"ws-macro"
                   ("Macro " ^ name ^ ": its rows are the holes.");
                 if Pxui.Ui.inspector_button ui ~key:"ws-inline" "Replace call with expansion"
                 then [ Syntax_edit (Flow_sop.Flow_edit.Inline_macro { node = n.path }) ] else []
             | None -> [] in
           (* the items of a list or a string: each can move up a place *)
           let movers = if n.synthetic || not (Flow_sop.Projection.reorderable n) then [] else
             List.concat_map (fun (r : P.row) -> match r.key with
               | Flow_sop.Flow_edit.Pos k when k >= 1 && k < 24 ->
                   if Pxui.Ui.inspector_button ui ~key:(Printf.sprintf "ws-move-%d" k)
                       (Printf.sprintf "Move item %d up" (k + 1))
                   then [ Syntax_edit (Flow_sop.Flow_edit.Move_item { node = n.path; pos = k }) ] else []
               | _ -> []) n.rows in
           if n.head = "settings/config" then Pxui.Ui.inspector_message ui ~key:"ws-startup-settings"
             "Title, size, frame rate and seed apply on restart.";
           let is_ref_slot (r : P.row) =
             (match r.expr with
              | Some { S.node = S.List [ { S.node = S.Sym "ref"; _ }; { S.node = S.Sym _; _ } ]; _ } -> true
              | _ -> false)
             || r.ty = Some Flow.Ty.Material
             || (r.ty = Some Flow.Ty.Geometry && String.starts_with ~prefix:"scene/" n.head) in
           let doc, _ = value.doc.Document.workspace in
           let sop_graphs = List.filter_map (fun (g : Flow.Workspace.graph) ->
             if g.context = Flow.Workspace.Sop then Some g.name else None) doc.checked.graphs in
           let material_graphs = List.filter_map (fun (g : Flow.Workspace.graph) ->
             if g.context = Flow.Workspace.Material then Some g.name else None) doc.checked.graphs in
           let ref_rows = List.filter_map (fun (r : P.row) ->
             if not (is_ref_slot r) then None else
             let is_material = r.ty = Some Flow.Ty.Material in
             let target = match r.expr with
               | Some { S.node = S.List [ { S.node = S.Sym "ref"; _ }; { S.node = S.Sym name; _ } ]; _ } -> name
               | _ -> "" in
             let choices = match (if is_material then material_graphs else sop_graphs) with
               | [] when not is_material -> [| "(none)" |]
               | gs ->
                   let list = if target <> "" && not (List.mem target gs) then target :: gs else gs in
                   Array.of_list (if is_material then list @ [ "new material" ] else list) in
             let field_name = "@ref:" ^ r.label in
             let current_val = if target <> "" then target else choices.(0) in
             let field = {
               Parameter.name = field_name;
               label = String.capitalize_ascii r.label;
               description = Some (if is_material then "Material graph reference" else "SOP graph reference");
               folder = [];
               impact = Parameter.Cook;
               primary = false;
               unit = None;
               vec3 = None;
               kind = Parameter.Choice_view choices;
               default = Parameter.Choice_value choices.(0);
               current = Parameter.Choice_value current_val;
             } in
             Some (r, { Pxui_shell.Inspector.path = field_name; fields = [ field ]; shown = true; locked = false;
                        drive = None; live = None; components = []; split = None }))
             n.rows in
           (* a switch's :active is a choice among its layouts, named from their panels *)
           let layout_names = match n.head, value.doc.Document.shell with
             | "ui/switch", Some { switch = Some sw; _ }
               when List.length sw.layouts
                    = List.length (List.filter (fun (r : P.row) -> match r.key with Flow_sop.Flow_edit.Pos _ -> r.kind <> P.Add | _ -> false) n.rows) ->
                 Some (Array.of_list (Editor_core.Panels.labels sw.layouts), sw.active)
             | _ -> None in
           let layout_row = Option.map (fun (names, active) ->
             let field = { Parameter.name = "@layout"; label = "Layout"; description = Some "The layout shown";
               folder = []; impact = Parameter.View; primary = true; unit = None; vec3 = None; kind = Parameter.Choice_view names;
               default = Parameter.Choice_value names.(0); current = Parameter.Choice_value names.(active) } in
             { Pxui_shell.Inspector.path = "@layout"; fields = [ field ]; shown = true; locked = false;
               drive = None; live = None; components = []; split = None }) layout_names in
           (* a split is sized by ratio or with one side fixed: the choice converts it, keeping
              the sizes it shows (flow.md 11.11) *)
           let size_names = [| "By ratio"; "First side fixed"; "Second side fixed" |] in
           let size_row = if n.head <> "ui/split" && n.head <> "ui/split-at" then None else begin
             let given key = List.exists (fun (r : P.row) -> r.key = Flow_sop.Flow_edit.Kw key && r.expr <> None) n.rows in
             let now = if given "first_size" then 1 else if given "second_size" then 2 else 0 in
             let field = { Parameter.name = "@size"; label = "Size"; description = Some "What the split is sized by";
               folder = []; impact = Parameter.View; primary = true; unit = None; vec3 = None; kind = Parameter.Choice_view size_names;
               default = Parameter.Choice_value size_names.(0); current = Parameter.Choice_value size_names.(now) } in
             Some { Pxui_shell.Inspector.path = "@size"; fields = [ field ]; shown = true; locked = false;
                    drive = None; live = None; components = []; split = None }
           end in
           let rows = Option.to_list layout_row @ Option.to_list size_row @ List.map snd ref_rows @ List.map (fun (parameter : Flow_sop.Port.parameter) ->
             let wired = match authored parameter with Some e -> not (literal e) | None -> false in
             { Pxui_shell.Inspector.path = parameter.path; fields = parameter.fields; shown = on_card_row parameter.path; locked = false;
               (* a computed argument reads as its expression, "=" first: typing another one, or
                  a number, replaces it; the cross removes it *)
               (* a plain name is a link, read as "<- name"; anything else is an expression *)
               drive = (match authored parameter with
                 | Some { S.node = S.Sym name; _ } when wired -> Some name
                 | Some e when wired -> Some ("=" ^ Flow.Lisp.flat e)
                 | _ -> None);
               (* what the drive gives now: the node's value at the probe *)
               live = (match parameter.fields with
                 | [ { Parameter.current = Parameter.Int_value i; _ } ] -> Some (string_of_int i)
                 | [ { current = Parameter.Float_value f; _ } ] -> Some (Printf.sprintf "%.6g" f)
                 | [ { current = Parameter.Bool_value b; _ } ] -> Some (string_of_bool b)
                 | _ -> None);
               components = []; split = None }) parameters in
           let expanded = List.filter_map (fun (f : Parameter.field_view) ->
             match f.folder with [] -> None | first :: _ -> Some first) fields |> List.sort_uniq String.compare in
           let num f =
S.make (S.Num (Flow.Lisp.float f)) in
           let edits = if rows = [] then [] else
             Pxui_shell.Inspector.flow_fields ui ~expanded ~width ~actions:false ~pins:true ~pin_click:true ~on_choice
               ~kind_label:(kind_label n.head)
               ~chips:(match value.scope_key with
                 | Some { evaluated = Some ev; _ } -> Navigator.chips ev
                 | _ -> []) rows
             |> List.filter_map (function
               | Pxui_shell.Inspector.Edited ("@layout", Param.Choice_value chosen) ->
                   Option.bind layout_names (fun (names, _) ->
                     Option.map (fun index -> Syntax_edit (Flow_sop.Flow_edit.Set_layout { graph; index }))
                       (Array.find_index (( = ) chosen) names))
               | Pxui_shell.Inspector.Edited ("@size", Param.Choice_value chosen) ->
                   Option.map (fun index ->
                     let how = List.nth [ `Ratio; `First; `Second ] index in
                     (* a split that is not on screen has no sizes to keep: half, or 240 points *)
                     let size = Option.value (resized n.path how) ~default:(match how with
                       | `Ratio -> `Ratio 0.5 | `First -> `First 240 | `Second -> `Second 240) in
                     Syntax_edit (Flow_sop.Flow_edit.Set_layout_size { node = n.path; size }))
                     (Array.find_index (( = ) chosen) size_names)
               | Pxui_shell.Inspector.Edited (name, edited) ->
                   (match List.find_opt (fun (r, _) -> ("@ref:" ^ r.P.label) = name) ref_rows with
                    | Some (r, _) ->
                        (match edited with
                         | Param.Choice_value "new material" ->
                             let name, make = new_material value in
                             Some (Syntax_batch ("New material", [ make; Flow_sop.Flow_edit.Set_arg
                               { node = n.path; key = r.key; sub = [];
                                 value = S.make (S.List [ S.make (S.Sym "ref"); S.make (S.Sym name) ]) } ]))
                         | Param.Choice_value chosen when chosen <> "(none)" && chosen <> "" ->
                             let syntax = S.make (S.List [ S.make (S.Sym "ref"); S.make (S.Sym chosen) ]) in
                             Some (Syntax_edit (Flow_sop.Flow_edit.Set_arg
                               { node = n.path; key = r.key; sub = []; value = syntax }))
                         | _ -> None)
                    | None ->
                        List.find_map (fun (parameter : Flow_sop.Port.parameter) ->
                          match List.find_index (fun (f : Parameter.field_view) -> f.name = name) parameter.fields with
                          | None -> None
                          | Some index ->
                              let syntax = match edited with
                                | Editor_core.Param.Float_value f -> num f
                                | Int_value i -> S.make (S.Num (string_of_int i))
                                | Bool_value b -> S.make (S.Sym (string_of_bool b))
                                | Text_value t | Choice_value t -> S.make (S.Str t) in
                              let syntax = if List.length parameter.fields <> 3 then syntax else
                                S.make (S.Vec (List.mapi (fun i (f : Parameter.field_view) ->
                                  if i = index then syntax else match f.current with
                                    | Editor_core.Param.Float_value x -> num x
                                    | Int_value x -> num (float x) | _ -> S.make (S.Num "0.0")) parameter.fields)) in
                              Some (Syntax_edit (Flow_sop.Flow_edit.Set_arg
                                { node = n.path; key = Flow_sop.Flow_edit.Kw parameter.path; sub = []; value = syntax })))
                          parameters)
               | Pxui_shell.Inspector.Pinned (path, want) ->
                   (* the dot: on the card or not; the default rule's own answer is stored as nothing *)
                   Option.map (fun (r : P.row) ->
                     Pin_row { node = n.path; label = r.label;
                               pin = if want = P.row_shown r then None else Some want }) (row_of path)
               | Pxui_shell.Inspector.Expression (path, text) ->
                   let key, sub = match String.index_opt path '.' with
                     | Some i -> String.sub path 0 i, List.filter_map Fun.id [ List.assoc_opt
                         (String.sub path (i + 1) (String.length path - i - 1)) [ "x", 0; "y", 1; "z", 2 ] ]
                     | None -> path, [] in
                   (match expression_text text with
                    | Ok value ->
                        Some (Syntax_edit (Flow_sop.Flow_edit.Set_arg { node = n.path;
                          key = Flow_sop.Flow_edit.Kw key; sub; value }))
                    | Error message -> Some (Declined message))
               | Pxui_shell.Inspector.Reset path ->
                   (match List.find_opt (fun (r, _) -> ("@ref:" ^ r.P.label) = path) ref_rows with
                    | Some (r, _) ->
                        Some (Syntax_edit (Flow_sop.Flow_edit.Set_arg
                          { node = n.path; key = r.key; sub = []; value = S.make (S.Sym "nil") }))
                    | None ->
                        Some (Syntax_edit (Flow_sop.Flow_edit.Disconnect { node = n.path;
                          key = Flow_sop.Flow_edit.Kw (List.hd (String.split_on_char '.' path)); fallback = None })))
               | _ -> None) in
           (* what the cook made of a geometry node: read-out rows, as the sheet's Output section *)
           (match geo with
            | Some (g : Flow_sop.Probe.geometry) ->
                ignore (Pxui.Ui.inspector_section ui ~key:"ws-output" ~expanded:true "Output" (fun () ->
                  Pxui.Ui.inspector_readout ui ~width ~key:"ws-output-points" ~label:"points"
                    (group_digits g.points);
                  Pxui.Ui.inspector_readout ui ~width ~key:"ws-output-prims" ~label:"prims"
                    (group_digits g.prims);
                  Option.iter (fun (x, y, z) ->
                    Pxui.Ui.inspector_readout ui ~width ~key:"ws-output-bounds" ~label:"bounds"
                      (Printf.sprintf "%.1f \xc3\x97 %.1f \xc3\x97 %.1f" x y z)) g.extent;
                  if g.groups <> [] then
                    Pxui.Ui.inspector_readout ui ~width ~key:"ws-output-groups" ~label:"groups"
                      (String.concat ", " g.groups)))
            | None -> ());
           (* the note above the binding in the Lisp: one line here, typing is one history entry;
              the last section, closed *)
           let note = if n.synthetic || Flow_sop.Projection.anonymous n then [] else begin
             let current = Option.value n.note ~default:"" in
             Option.value ~default:[] (Pxui.Ui.inspector_section ui ~key:"ws-note-section" "Note" (fun () ->
               if String.contains current '\n' then begin
                 Pxui.Ui.inspector_message ui ~key:"ws-note-lines" "A note of several lines is edited in the text pane.";
                 []
               end else begin
                 let box, control_x, control_y, control_w = Pxui.Ui.inspector_row ui ~width ~key:"ws-note" ~label:"note" () in
                 let text = Pxui.Ui.within ui box (fun () ->
                   fst (Pxui.Ui.value_field ui ~at:(control_x, control_y) ~w:control_w ~h:20.
                     ~left:true ~valid:(fun _ -> true) "ws-note-field" current)) in
                 if text = current then []
                 else [ Syntax_edit (Flow_sop.Flow_edit.Set_note { node = n.path; text }) ]
               end)) end in
           let iterations = Probe.iterations records n ~probes in
           let zone = List.nth_opt (List.rev chain) 0 in
           let picks = match zone with
             | Some z when Array.length iterations > 0 ->
                 Pxui.Ui.inspector_message ui ~key:"ws-runs"
                   (Printf.sprintf "Inside %s: runs %d times. %s" (List.nth z (List.length z - 1))
                      (Option.value ~default:(Array.length iterations) footer.runs)
                      (if n.invariant then "The same every time, so it can move out of the loop."
                       else "It changes with the loop variable."));
                 let current = List.nth probes (List.length probes - 1) in
                 List.concat (List.init (min 64 (Array.length iterations)) (fun k ->
                   if Pxui.Ui.inspector_button ui ~key:(Printf.sprintf "ws-iter-%d" k)
                       (Printf.sprintf "%s%d  %s" (if k = current then "► " else "  ") (k + 1) iterations.(k))
                   then [ Pxui_graph.Scope.Probe_set { zone = z; index = k } ] else []))
             | _ -> [] in
           on_card := List.length (List.filter (fun (r : Pxui_shell.Inspector.flow_row) -> r.shown && r.path.[0] <> '@') rows);
           hoist @ macro @ note @ movers @ edits, picks) in
           (* the sheet's bar: what a field takes, and how many rows are on the card *)
           if not (window || narrow) then
             Pxui.Ui.inspector_bar ui ~hints:[ "s", "pin row to card"; "\xe2\x8c\xa5 click", "type a value" ] ~count:!on_card;
           fst flags @ rename @ reset_all @ requests, snd flags @ picks)
  | _ -> [], []

(* The node of the graph pane that a lowered node of the open object was made by, at the iterations
   the selectors probe. *)
let node_path value node_id =
  match value.scope_key, value.doc.Document.workspace with
  | Some { scope; records = Some records; _ }, (_, lowered) ->
      let chains = Flow_sop.Probe.chains scope in
      let rec search (s : Flow_sop.Projection.scope) =
        List.find_map (fun (n : Flow_sop.Projection.node) ->
          let probes = List.map (fun zone ->
            Option.value ~default:0 (Layout_by_path.Path_map.find_opt zone value.probes))
            (Option.value ~default:[] (Hashtbl.find_opt chains n.path)) in
          match Flow_sop.Probe.plan_node records n.path ~probes with
          | Some plan when Flow_sop.Network.Int_map.find_opt plan lowered.compiled = Some node_id ->
              Some n.path
          | _ -> Option.bind n.zone (fun (z : Flow_sop.Projection.zone) -> search z.scope)) s.nodes in
      search scope
  | _ -> None

let stored_projection value =
  match Level_map.find_opt value.level value.projections with
  | Some projection -> projection
  | None -> (match value.level with
    | Document.Scene -> List_view
    | Inside id when kind value id = Some "geometry" -> Graph_view
    | Inside _ -> List_view)

(* Any of the panels that hold the graph pane's views is on screen. *)
let graph_family value = has_panel value Pxui_shell.Layout.Graph || has_panel value List
  || has_panel value Lisp

(* What the graph panel shows: the view it says, whatever other panels the layout has. *)
let projection = stored_projection

(* Which keys the focused panel takes: the list's and the text pane's own panels, else
   the graph panel's projection. *)
let listing value = value.focus = List || (value.focus <> Lisp && projection value = List_view)
let texting value = value.focus = Lisp || (value.focus <> List && projection value = Text_view)

(* ---- panel instances: every leaf draws, with its own list, text pane or outline ---- *)

let fresh_local () = { rows = Pxui_shell.Tree.create (); code = Text_pane.initial; nav = Navigator.initial }
let local_of value key = match List.assoc_opt key value.locals with Some l -> l | None -> fresh_local ()
let put_local key f locals =
  (key, f (match List.assoc_opt key locals with Some l -> l | None -> fresh_local ())) :: List.remove_assoc key locals

(* The open panels that hold a list, a text pane or an outline: a graph panel holds the one its
   view shows. *)
let panel_hosts value =
  List.filter_map (fun (path, panel) ->
    if not (visible value.workspace panel) || (panel_state value path).collapsed then None else
    let key = panel_key value.doc path in
    let kind = match panel with
      | Pxui_shell.Layout.List -> Some `List | Lisp -> Some `Text | Outline -> Some `Outline
      | Graph ->
          (match projection (as_pane value (key, path)) with
           | List_view -> Some `List | Text_view -> Some `Text | Graph_view -> None)
      | View _ | Inspector | Timeline -> None in
    Option.map (fun kind -> key, path, panel, kind) kind)
    (Editor_core.Panels.leaves (shell_tree value value.workspace))

(* The editor as the graph panel a leaf shows has it: a graph leaf its own, a leaf tied by [:of]
   that panel's, any other the pane in use. *)
let shown_as value (key, path, panel) =
  if panel = Pxui_shell.Layout.Graph then as_pane value (key, path)
  else match tied value path with Some target -> as_pane value target | None -> value

(* [tree], [text] and [outline] follow the focus like the graph pane does: each belongs to the
   focused panel of its kind, else to the one it was, else to the first one open; the panel left
   keeps its own in [locals]. *)
let follow_hosts value ~focus_path hosts =
  let focused = Option.map (panel_key value.doc) focus_path in
  let pick kind current =
    let keys = List.filter_map (fun (key, _, _, k) -> if k = kind then Some key else None) hosts in
    match focused, current with
    | Some key, _ when List.mem key keys -> Some key
    | _, Some key when List.mem key keys -> current
    | _ -> List.nth_opt keys 0 in
  let move value ~target ~current ~set ~save ~load =
    match target, current with
    | None, _ -> value
    | _ when target = current -> value
    | _, None -> set value target  (* the first one: the state so far is its *)
    | Some key, Some old ->
        let value = { value with locals = put_local old (save value) value.locals } in
        load (set value target) (local_of value key) in
  let value = move value ~target:(pick `List value.list_at) ~current:value.list_at
    ~set:(fun v list_at -> { v with list_at }) ~save:(fun v l -> { l with rows = v.tree })
    ~load:(fun v l -> { v with tree = l.rows }) in
  let value = move value ~target:(pick `Text value.text_at) ~current:value.text_at
    ~set:(fun v text_at -> { v with text_at }) ~save:(fun v l -> { l with code = v.text })
    ~load:(fun v l -> { v with text = l.code }) in
  move value ~target:(pick `Outline value.outline_at) ~current:value.outline_at
    ~set:(fun v outline_at -> { v with outline_at }) ~save:(fun v l -> { l with nav = v.outline })
    ~load:(fun v l -> { v with outline = l.nav })

(* The start keywords of the document, by panel key. *)
let start_of (doc : Document.t) = match doc.shell with
  | None -> { on = None; views = []; tabs = [] }
  | Some s ->
      let keyed l = List.map (fun (path, v) -> panel_key doc path, v) l in
      { on = Option.map (panel_key doc) s.start.focus; views = keyed s.start.graph_views; tabs = keyed s.start.tabs }

(* The editor follows a start keyword when its value in the text changed (flow.md 11.11): on
   opening, a reload, a preset, an edit, undo.  What did not change is left as the user has it. *)
let follow_start value =
  let now = start_of value.doc and was = value.started in
  if now = was then value else
  let leaves = Editor_core.Panels.leaves (shell_tree value value.workspace) in
  let path_of key = List.find_map (fun (path, panel) ->
    if panel_key value.doc path = key then Some (path, panel) else None) leaves in
  let changed now was = List.filter (fun (key, v) -> List.assoc_opt key was <> Some v) now in
  let value = match now.on with
    | Some key when now.on <> was.on ->
        (match path_of key with
         | Some (path, panel) -> { value with focus = panel; focus_path = Some path }
         | None -> value)
    | _ -> value in
  let value = List.fold_left (fun value (key, view) ->
    let view = match view with "list" -> List_view | "text" -> Text_view | _ -> Graph_view in
    if value.graph_pane = Some key then { value with projections = Level_map.add value.level view value.projections }
    else match path_of key with
      | Some (path, _) ->
          let pane = stash (as_pane value (key, path)) in
          { value with graph_panes = (key, { pane with views = Level_map.add pane.at view pane.views })
                                     :: List.remove_assoc key value.graph_panes }
      | None -> value) value (changed now.views was.views) in
  let value = List.fold_left (fun value (key, tab) ->
    let tab = match tab with "graph" -> Text_pane.Graph | "document" -> Document | _ -> Selection in
    if value.text_at = Some key || value.text_at = None then { value with text = { value.text with tab } }
    else { value with locals = put_local key (fun l -> { l with code = { l.code with tab } }) value.locals })
    value (changed now.tabs was.tabs) in
  { value with started = now }

(* The workspace graph the pane shows with zones and selectors: the one a
   [(ui/graph "name")] panel names, else the one the outline picked, else the graph of the
   geometry object opened (the one its network was lowered from, else the
   [sop] graph its label names), of the World opened, or the scene graph at the scene level.
   A level without such a graph shows its list only. *)
(* The lowered sop graph a geometry object instantiates, by its network. *)
let graph_of_object value id = Document.object_graph value.doc id

let graph_name value = match value.doc.Document.workspace with
  | ws, _ ->
      let exists name = List.exists (fun (g : Flow.Workspace.graph) -> g.name = name) ws.checked.graphs
        || (String.length name > 4 && String.sub name 0 4 = "def:"
            && List.exists (fun (g : Flow.Workspace.graph) -> "def:" ^ g.name = name) ws.checked.defs) in
      (* the graph the pane's own leaf pins *)
      let named = Option.bind value.doc.Document.shell (fun s ->
        Option.bind (graph_path value) (fun path -> List.assoc_opt path s.Document.named)) in
      (match (if value.pane_graph <> None then value.pane_graph else named), value.level with
       | Some name, _ when exists name -> Some name
       | _, Document.Inside id when kind value id = Some "geometry" ->
           (match graph_of_object value id with
            | Some _ as name -> name
            | None -> Option.bind (Edit_graph.find (scene value) ~node_id:id) (fun node ->
                let name = Node.label node in if exists name then Some name else None))
       | _, Inside id when kind value id = Some "world" ->
           List.find_map (fun (g : Flow.Workspace.graph) ->
             if g.context = Flow.Workspace.World then Some g.name else None) ws.checked.graphs
       | _, Document.Scene ->
           List.find_map (fun (g : Flow.Workspace.graph) ->
             if g.context = Flow.Workspace.Scene then Some g.name else None) ws.checked.graphs
       | _ -> None)

(* For the crash report and tests: the graph of every graph panel, and the floating windows. *)
let graph_panels value =
  String.concat ", " (List.map (fun leaf -> Option.value ~default:"-" (graph_name (as_pane value leaf)))
    (graph_leaves value))
let windows value =
  String.concat ", " (List.filter_map (fun (path, panel) ->
    Option.map (fun (x, y, w, h) -> Printf.sprintf "%s %d %d %d %d"
      (String.lowercase_ascii (Editor_core.Panels.name panel)) x y w h) (panel_state value path).window)
    (Editor_core.Panels.leaves (shell_tree value value.workspace)))

(* Every panel by its key's last name, the focused one starred, with what is its own: a text
   pane's tab and draft, a list's focus, folds and filter, an outline's search. *)
let panels_line value =
  let hosts = panel_hosts value in
  String.concat "; " (List.map (fun (path, panel) ->
    let key = panel_key value.doc path in
    let name = String.lowercase_ascii (Editor_core.Panels.name panel) ^ " " ^ List.nth key (List.length key - 1)
      ^ (if value.focus = panel && value.focus_path = Some path then "*" else "") in
    let own = List.find_map (fun (k, p, _, kind) -> if k = key && p = path then Some kind else None) hosts in
    match own with
    | Some `Text -> name ^ ": " ^ Text_pane.summary (if Some key = value.text_at then value.text else (local_of value key).code)
    | Some `List -> name ^ ": " ^ Pxui_shell.Tree.summary (if Some key = value.list_at then value.tree else (local_of value key).rows)
    | Some `Outline -> name ^ Printf.sprintf ": search %S"
        (Navigator.query (if Some key = value.outline_at then value.outline else (local_of value key).nav))
    | None -> name)
    (Editor_core.Panels.leaves (shell_tree value value.workspace)))

(* Follow a reference: the pane shows [graph], and [u] comes back to what it showed. *)
let remember value =
  { value with back = List.filteri (fun i _ -> i < 32) ((value.level, value.pane_graph) :: value.back) }

let go value graph =
  if graph_name value = Some graph then value else { (remember value) with pane_graph = Some graph }

(* What the selected node of the graph pane references: the graph its [(ref name)] names, the
   [:material] of a sop/material first (a material node follows to its surface). *)
let follow_target ?path value =
  let ws, _ = value.doc.Document.workspace in
  let module S = Flow.Syntax in
  let exists name = List.exists (fun (g : Flow.Workspace.graph) -> g.name = name) ws.checked.graphs in
  let reference (e : S.t) = match e.node with
    | S.List [ { node = S.Sym "ref"; _ }; { node = S.Sym name; _ } ] when exists name -> Some name
    | _ -> None in
  match (match path with Some p -> [ p ] | None -> Pxui_graph.Scope.selected value.scope_view) with
  | [ path ] when graph_name value <> None ->
      let arg key = Option.bind (Flow_sop.Flow_edit.arg_text ws.source path key) reference in
      (match arg (Kw "material") with
       | Some _ as found -> found
       | None ->
           (match Flow_sop.Flow_edit.arg_text ws.source path Whole with
            | Some { node = S.List (_ :: args); _ } -> List.find_map reference args
            | _ -> None))
  | _ -> None

(* [follow_target], else the graph of the object selected in the list *)
let peek_target value =
  match follow_target value with
  | Some _ as found -> found
  | None -> Option.bind (Selection.selected value.selection) (fun id ->
      match kind value id with
      | Some "geometry" -> graph_of_object value id
      | _ -> None)

(* [i] in a viewport with nothing selected follows to the scene it shows: the graph its
   [(ref scene)] names, else the first scene graph. *)
let viewport_target value =
  let ws, _ = value.doc.Document.workspace in
  match value.focus with
  | Pxui_shell.Layout.View key when Selection.selected value.selection = None ->
      let named = Option.bind value.doc.Document.shell (fun shell ->
        match List.assoc_opt key shell.preview_sources with
        | Some { scene_ref = Some { node = Flow.Syntax.List [ { node = Sym "ref"; _ }; { node = Sym name; _ } ]; _ }; _ } ->
            Some name
        | _ -> None) in
      (match named with
       | Some _ -> named
       | None -> List.find_map (fun (g : Flow.Workspace.graph) ->
           if g.context = Flow.Workspace.Scene then Some g.name else None) ws.checked.graphs)
  | _ -> None

(* The route taken, as the graph header shows it: scene > shards > cobalt (the last three) *)
let route value =
  List.rev_map (fun (level, pane_graph) -> graph_name { value with level; pane_graph }) value.back
  @ [ graph_name value ]
  |> List.filter_map Fun.id
  |> (fun names -> List.filteri (fun i _ -> i >= List.length names - 3) names)
  |> String.concat " > "

let scope_name value = if projection value = Graph_view then graph_name value else None

(* The lowered node of the node selected in the graph pane, at the iteration its zones probe. *)
let scope_node value =
  match value.scope_key, value.doc.Document.workspace, Pxui_graph.Scope.selected value.scope_view with
  | Some { scope; records = Some records; _ }, (_, lowered), [ path ] when scope_name value <> None ->
      Option.bind (Flow_sop.Projection.find scope path) (fun (n : Flow_sop.Projection.node) ->
        let chain = Option.value ~default:[] (Hashtbl.find_opt (Flow_sop.Probe.chains scope) n.path) in
        let probes = List.map (fun p ->
          Option.value ~default:0 (Layout_by_path.Path_map.find_opt p value.probes)) chain in
        Option.bind (Flow_sop.Probe.plan_node records n.path ~probes) (fun id ->
          Option.bind (Flow_sop.Network.Int_map.find_opt id lowered.compiled) (fun node_id ->
            Option.map (fun node -> n.path, node) (compiled_node value node_id))))
  | _ -> None


let lit_tags value =
  match value.doc.Document.workspace, value.scope_key,
        Pxui_graph.Scope.selected value.scope_view with
  | (_, lowered), Some { scope; _ }, [ site ] when scope_name value <> None ->
      (match value.lit with
       | Some c when c.site = site && c.at == value.probes && c.lowered == lowered
           && c.scope == scope -> c.tags, value.lit
       | _ ->
           let chain = Option.value ~default:[]
               (Hashtbl.find_opt (Flow_sop.Probe.chains scope) site) in
           let iter = List.map (fun zone ->
             Option.value ~default:0 (Layout_by_path.Path_map.find_opt zone value.probes)) chain in
           let tags = Pick.Set.of_list (Flow_sop.Lower.tags lowered ~site ~iter) in
           tags, Some { site; at = value.probes; lowered; scope; tags })
  | _ -> Pick.Set.empty, None

(* The nodes of the pane's graph that the last failed cook names, each with its diagnostic's code
   (the pane draws the sheet's failed state on them). *)
let failed_nodes value =
  match Cook.failed_node value.cook, value.scope_key, value.doc.Document.workspace with
  | Some (code, node_id), Some { scope; records = Some records; _ }, (_, lowered)
    when scope_name value <> None ->
      let rec nodes (s : Flow_sop.Projection.scope) = List.concat_map (fun (n : Flow_sop.Projection.node) ->
        n :: (match n.zone with Some z -> nodes z.scope | None -> [])) s.nodes in
      let chains = Flow_sop.Probe.chains scope in
      List.filter_map (fun (n : Flow_sop.Projection.node) ->
        let probes = List.map (fun p ->
          Option.value ~default:0 (Layout_by_path.Path_map.find_opt p value.probes))
          (Option.value ~default:[] (Hashtbl.find_opt chains n.path)) in
        match Flow_sop.Probe.plan_node records n.path ~probes with
        | Some id when Flow_sop.Network.Int_map.find_opt id lowered.compiled = Some node_id -> Some (n.path, code)
        | _ -> None) (nodes scope)
  | _ -> []

(* Lay the workspace pane out again when the document, the probes or the
   graph changed; the footers are rebuilt when the recording evaluation, the
   cook's geometry counts or (a live document) the time changed.  The
   evaluation runs once per checked source, never per move or per frame. *)
let sync_scope value = match graph_name value, value.doc.Document.workspace, Lazy.force value.flow_catalog with
  | Some name, (ws, lowered), Some catalog ->
      let module M = Layout_by_path.Path_map in
      let previous = value.scope_key in
      let same k = k.ws == ws && k.graph = name in
      let moved = match previous with
        | Some k -> not (same k && k.probe_map == value.probes) | None -> true in
      let evaluated = match previous with
        | Some k when k.ws.checked == ws.checked -> k.evaluated
        | _ -> Result.to_option (Flow.Eval.static ~record:true ws.checked) in
      let time = if fst (Flow_sop.Lower.counts lowered) > 0
        then Some (Sketch_support.Timeline.time value.timeline) else None in
      let summaries = value.cook.Cook.summaries in
      let fresh = match previous with
        | Some k -> not (k.evaluated == evaluated && k.summaries == summaries && k.time = time)
        | None -> true in
      if not moved && not fresh then value else begin
        let scope = match previous with
          | Some k when not moved -> k.scope
          | _ -> Flow_sop.Projection.of_graph catalog ws.checked name in
        let wires = match Option.bind value.doc.Document.shell (fun s -> s.Document.wires) with
          | Some "rect" -> `Rect
          | _ -> `Straight in
        let scope_view = if not moved then Pxui_graph.Scope.with_wires wires value.scope_view else begin
          let layout = ws.layout in
          let display = match M.find_opt [ name ] layout.display with
            | Some p -> Some p
            | None ->
                (match scope.result with
                 | Link target -> Some [ name; target ]
                 | Node target_path -> Some target_path
                 | Literal _ -> None) in
          let layouts = match value.doc.Document.shell with
            | Some { switch = Some _; _ } when Option.map (fun (g : Flow.Workspace.graph) -> g.name)
                (Workspace_doc.editor_graph (fst value.doc.Document.workspace)) = Some name -> List.map fst (layouts value)
            | _ -> [] in
          Pxui_graph.Scope.with_scope ~wires ~layouts ~key:name scope value.scope_view
            ~at:(fun path -> M.find_opt path layout.at)
            ~level:(fun path -> match M.find_opt path layout.level, M.find_opt path layout.pinned with
              | None, None -> None
              | level, pinned -> Some (Option.value ~default:Flow_sop.Projection.Card level,
                                       Option.value ~default:false pinned))
            ~pin:(fun path label -> Option.bind (M.find_opt path layout.rows) (Layout_by_path.String_map.find_opt label))
            ~collapsed:(fun path -> Option.value ~default:false (M.find_opt path layout.collapsed))
            ~probe:(fun path -> Option.value ~default:0 (M.find_opt path value.probes))
            ~frames:(fun path -> List.map (fun (f : Layout_by_path.frame) -> f.title, f.at, f.size)
              (Option.value ~default:[] (M.find_opt path layout.frames)))
            ?display end in
        let geometry id = Option.bind (Flow_sop.Network.Int_map.find_opt id lowered.compiled)
          (fun node_id -> Option.bind (node_owner value node_id) (fun object_id ->
            Cook.geometry value.cook ~object_id ~node_id)) in
        (* a pick in another graph's geometry asked for its node to be selected here *)
        let scope_view, select_later =
          if value.select_later <> [] && List.for_all (fun p -> List.hd p = name) value.select_later
          then Pxui_graph.Scope.select value.select_later scope_view, [] else scope_view, value.select_later in
        let element zone k = Option.map (fun (name, (x, y, z)) -> [ name, Flow.Eval.Vec3 (x, y, z) ])
          (Flow_sop.Lower.zone_element lowered zone k) in
        let records = Option.map (Flow_sop.Probe.make ?time ~geometry
          ~dynamic:(Flow_sop.Lower.zone_count lowered) ~element) evaluated in
        let scope_view = match records with
          | Some records when fresh || moved -> Pxui_graph.Scope.with_records records scope_view
          | _ -> scope_view in
        let targets = match records, previous with
          | Some _, Some k when not moved && k.evaluated == evaluated -> k.targets
          | Some records, _ ->
              List.filter_map (fun id ->
                Option.bind (Flow_sop.Network.Int_map.find_opt id lowered.compiled) (fun node_id ->
                  Option.map (fun object_id -> object_id, node_id) (node_owner value node_id)))
                (Flow_sop.Probe.geometry_targets records scope
                   ~probe:(fun path -> Option.value ~default:0 (M.find_opt path value.probes)))
          | None, _ -> [] in
        { value with scope_view; select_later; scope_key = Some { ws; probe_map = value.probes; graph = name;
            evaluated; summaries; time; records; scope; targets } }
      end
  | _ -> value

(* Where a node is added from the list or the pane: the graph the level shows, else the scene
   or World graph that adding an object or a layer creates. *)
let add_target value =
  let ws, _ = value.doc.Document.workspace in
  match graph_name value with
  | Some name ->
      let context = match List.find_opt (fun (g : Flow.Workspace.graph) -> g.name = name) ws.checked.graphs with
        | Some g -> g.context | None -> Flow.Workspace.Sop in
      Some (name, context)
  | None ->
      (match value.level with
       | Document.Scene -> Some ("scene", Flow.Workspace.Scene)
       | Inside id when kind value id = Some "world" -> Some ("world", World)
       | _ -> None)

(* The menu's "Value" entries: a value is a binding with an expression (a number, the time, an
   operator call), which the other nodes read by name ("=number", "=t", "=+", ...). *)
let value_entries =
  (* the colour of a value's square: what it makes, as far as its section says *)
  let entry ?output sub key label =
    let output = match output, sub with
      | Some ty, _ -> ty | None, "Compare" -> Flow.Ty.Bool | None, "Text" -> Text
      | None, "Convert" when key = "=int" -> Int | None, _ -> Float in
    { Pxui_graph.Node_menu.key; label; category = [ "Value"; sub ]; arity = 0; context = "value"; output;
      off = None } in
  let categorize = function
    | "int" | "float" | "floor" | "round" | "ceil" -> "Convert"
    | "<" | ">" | "<=" | ">=" | "=" | "and" | "or" | "not" -> "Compare"
    | "str" -> "Text"
    | "range" | "linspace" | "count" | "first" | "last" | "rest" | "nth" | "reverse" | "take" | "drop" -> "List"
    | _ -> "Math" in
  [ entry "Math" "=number" "Number"; entry "Math" "=t" "Time (t)"; entry ~output:Flow.Ty.Vec3 "Math" "=vec3" "Vector";
    entry "Text" "=text" "Text"; entry "Text" "=str" "str" ]
  @ List.map (fun op -> entry (categorize op) ("=" ^ op) op) Flow.Workspace.value_ops

(* the expression and the name a "Value" entry makes *)
let value_expression context key =
  let module S = Flow.Syntax in
  let mk node = S.make node in
  let num n = mk (S.Num n) in
  let op = String.sub key 1 (String.length key - 1) in
  match op with
  | "number" -> mk (S.Num "1.0"), "value"
  | "t" -> mk (S.Sym "t"), "time"
  | "vec3" -> mk (S.Vec [ num "0.0"; num "0.0"; num "0.0" ]), "vector"
  | "text" -> mk (S.Str "text"), "text"
  | "str" -> mk (S.List [ mk (S.Sym "str"); mk (S.Str "text") ]), "text"
  | op ->
      let signature = Flow.Workspace.op_signature context op in
      let argument (label, ty) = match Flow_sop.Flow_edit.default_for ty label with
        | Some d -> d
        | None -> (match ty with
            | Flow.Ty.List _ -> mk (S.List [ mk (S.Sym "range"); num "4" ])
            | _ -> num "0.5") in
      let args = match signature with
        | Some s -> List.map argument s.Flow.Workspace.pos | None -> [] in
      mk (S.List (mk (S.Sym op) :: args)),
      (match op with
       | "+" -> "sum" | "-" -> "difference" | "*" -> "product" | "/" -> "quotient"
       | "<" | ">" | "<=" | ">=" | "=" -> "test" | op -> op)

(* A kind picked in the node menu, as one [Add_node] at the selected zone (else the graph
   body), wired to the selected node when the kind takes a geometry input. *)
let scope_add value key =
  match add_target value with
  | Some (_, Flow.Workspace.Scene) when List.mem key [ "geometry"; "world" ] || String.starts_with ~prefix:"of:" key ->
      (* composition: geometry brings its SOP graph, World its world graph, one gesture each *)
      let geometry existing label =
        [ Syntax_batch (label, Editor_document.Scene_sync.add_geometry value.doc ~existing) ] in
      if key = "geometry" then geometry None "Add geometry"
      else if key = "world" then
        (match Editor_document.Scene_sync.add_world value.doc with
         | Ok ops -> [ Syntax_batch ("Add World", ops) ]
         | Error message -> [ Declined message ])
      else
        let graph = String.sub key 3 (String.length key - 3) in
        geometry (Some graph) ("Add geometry of " ^ graph)
  | Some (_, Flow.Workspace.Scene) when key = "material" ->
      [ Syntax_batch ("New material", [ snd (new_material value) ]) ]
  | Some (graph, Flow.Workspace.Scene) when key = "merge" ->
      (* several selected objects move into a new merge; with none selected, an empty merge *)
      (match Pxui_graph.Scope.selected value.scope_view with
       | _ :: _ :: _ as nodes ->
           let ws, _ = value.doc.Document.workspace in
           [ Syntax_edit (Flow_sop.Flow_edit.Group_merge { nodes;
               name = Flow_sop.Flow_edit.fresh_name ws.source ~root:graph "group" }) ]
       | _ ->
           let ws, _ = value.doc.Document.workspace in
           [ Syntax_edit (Flow_sop.Flow_edit.Add_node { scope = [ graph ];
               name = Flow_sop.Flow_edit.fresh_name ws.source ~root:graph "group";
               expr = Flow.Syntax.make (Flow.Syntax.List [ Flow.Syntax.make (Flow.Syntax.Sym "scene/merge") ]) }) ])
  | Some (graph, context) ->
      let ws, _ = value.doc.Document.workspace in
      let is_value = String.length key > 0 && key.[0] = '=' in
      let material_of = String.starts_with ~prefix:"of-material:" key in
      let arity = match List.find_opt (fun f -> Edit_graph.factory_key f = key)
          (catalog value context) with
        | Some factory -> Edit_graph.factory_arity factory | None -> if material_of then 1 else 0 in
      let selected = Pxui_graph.Scope.selected value.scope_view in
      let scope, input = match selected with
        | _ when (context = Flow.Workspace.Scene || context = World) && not is_value ->
            (* an object joins the scene's merge and a layer goes on top of the stack: the
               edit itself does that *)
            [ graph ], None
        | [ path ] when List.length path >= 2 ->
            let last = List.nth path (List.length path - 1) in
            List.filteri (fun i _ -> i < List.length path - 1) path,
            (if arity > 0 && last.[0] <> ':' && last.[0] <> '@' then Some last else None)
        | _ ->
            (* nothing selected: a kind with an input reads the graph's result, so the text
               still checks (a required input is never left open) *)
            let result = match value.scope_key with
              | Some { scope = { Flow_sop.Projection.result = Link name; _ }; _ } -> Some name
              | _ -> None in
            [ graph ], (if arity > 0 then result else None) in
      let expr, base =
        if is_value then value_expression context key
        else begin
          let head = Flow.Syntax.make (Flow.Syntax.Sym (Flow.Workspace.context_name context ^ "/"
            ^ (if material_of then "material" else key))) in
          let geometry = match context, key, List.find_opt (fun (g : Flow.Workspace.graph) ->
              g.context = Flow.Workspace.Sop) ws.checked.graphs with
            | Scene, "geometry", Some g -> [ Flow.Syntax.make (Flow.Syntax.List
                [ Flow.Syntax.make (Flow.Syntax.Sym "ref"); Flow.Syntax.make (Flow.Syntax.Sym g.name) ]) ]
            | _ -> [] in
          Flow.Syntax.make (Flow.Syntax.List (head :: geometry
            @ (match input with
               | Some n -> [ Flow.Syntax.make (Flow.Syntax.Sym n) ]
               | None -> if arity > 0 && geometry = [] then [ Flow.Syntax.make (Flow.Syntax.Sym "nil") ] else [])
            @ (if material_of then [ Flow.Syntax.make (Flow.Syntax.Kw "material");
                Flow.Syntax.make (Flow.Syntax.List [ Flow.Syntax.make (Flow.Syntax.Sym "ref");
                  Flow.Syntax.make (Flow.Syntax.Sym (String.sub key 12 (String.length key - 12))) ]) ] else []))),
          (if material_of then "material" else key)
        end in
      let name = Flow_sop.Flow_edit.fresh_name ws.source ~root:graph base in
      [ Syntax_edit (Flow_sop.Flow_edit.Add_node { scope; name; expr }) ]
  | None -> [ Declined "Open a graph to add a node to it" ]

let enterable value id = match kind value id with
  | Some ("geometry" | "world") ->
      Document.Int_map.mem id value.doc.Document.networks
  | Some _ | None -> false

(* Switch the open level: nothing is selected there, and the list starts again. *)
let open_level value level =
  if level = value.level then value else
  let () = Pxui.Ui.unfocus value.ui in
  let world = match level with
    | Document.Inside id -> kind value id = Some "world"
    | Scene -> false in
  { value with level; pane_graph = None; selection = Selection.empty; map_view = world;
    tree = Pxui_shell.Tree.create () }

(* The node of an object's graph the viewport shows instead of its result: a node inside a loop that
   [v] marked in the pane (the layout's display), at the iterations the selectors probe. *)
let display_node value id =
  match value.scope_key, value.doc.Document.workspace with
  | Some { scope; records = Some records; graph; _ }, (ws, lowered)
    when graph_of_object value id = Some graph ->
      Option.bind (Layout_by_path.Path_map.find_opt [ graph ] ws.layout.display) (fun path ->
        let chain = Option.value ~default:[] (Hashtbl.find_opt (Flow_sop.Probe.chains scope) path) in
        let probes = List.map (fun zone ->
          Option.value ~default:0 (Layout_by_path.Path_map.find_opt zone value.probes)) chain in
        Option.bind (Flow_sop.Probe.plan_node records path ~probes) (fun plan ->
          Flow_sop.Network.Int_map.find_opt plan lowered.compiled))
  | _ -> None

(* The geometry objects to cook: visible ones, each with its network. *)
let geometry_objects value =
  List.filter_map (fun id ->
    match Edit_graph.find (scene value) ~node_id:id,
        Document.Int_map.find_opt id value.doc.Document.networks with
    | Some node, Some network when Objects.visible node
        && not (Edit_graph.is_bypassed (scene value) ~node_id:id) ->
        Option.map (fun displayed ->
          let shown = match display_node value id with
            | Some node when Edit_graph.find network.Document.graph.geometry ~node_id:node <> None -> node
            | _ -> displayed in
          id, network.Document.graph, shown) network.displayed
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

(* The object in focus (the selected scene object, or the one whose network is open): its world
   transform, its cooked bounds in its own space, and its name. *)
let selected_bounds value =
  Option.bind (piece value) (fun (piece : _ Cook.piece) ->
    Option.bind piece.bounds (fun bounds ->
      Option.map (fun node -> Objects.world (scene value) piece.id, bounds, Node.label node)
        (Edit_graph.find (scene value) ~node_id:piece.id)))
let no_graph = Sop.points [||]
let graph value = match Option.bind (focus_object value) (fun id ->
    List.assoc_opt id value.cook.Cook.graphs), piece value with
  | Some graph, _ -> graph
  | None, Some piece -> piece.graph
  | None, None -> no_graph
let displayed_node = graph
let settings value = value.doc.Document.settings
let timeline value = value.timeline
let selected_node value = match scope_node value with
  | Some (_, node) -> Some node
  | None -> Option.bind (Selection.selected value.selection)
      (fun node_id -> Edit_graph.find (document value) ~node_id)
(* Scoped SOP handles use their owning object's transform. Navigation
   selection uses the open object or the scene object's parent chain. *)
let space value = match Option.bind (scope_node value) (fun (_, node) -> node_owner value (Node.id node)) with
  | Some owner -> Objects.world (scene value) owner
  | None -> match value.level with
  | Inside id when kind value id = Some "geometry" -> Objects.world (scene value) id
  | Inside _ -> Mat4.identity
  | Scene -> (match Selection.selected value.selection with
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

(* The objects as a tree by parent, siblings in id order. *)
let scene_rows ?active document =
  let infos = Edit_graph.inspect document in
  let children = Hashtbl.create 16 in
  List.iter (fun (info : Edit_graph.node_info) ->
    let parent = if Array.length info.inputs > 0 then info.inputs.(0) else None in
    Hashtbl.replace children parent
      (info :: Option.value ~default:[] (Hashtbl.find_opt children parent))) infos;
  let sorted parent = List.sort (fun (a : Edit_graph.node_info) b -> Int.compare a.id b.id)
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

(* The network as list rows [(id, depth, link)], sources first: rows follow each node's first
   input, other inputs nest one level under the node that consumes them, and a node reached
   twice repeats as a [link] row. *)
let trunk (network : Flow_sop.Network.t) =
  let infos = Edit_graph.inspect network.geometry in
  let consumed = Hashtbl.create 64 and inputs = Hashtbl.create 64 in
  List.iter (fun (info : Edit_graph.node_info) ->
    Hashtbl.replace inputs info.id (Array.to_list info.inputs);
    Array.iter (Option.iter (fun source -> Hashtbl.replace consumed source ())) info.inputs) infos;
  let ids = List.map (fun (info : Edit_graph.node_info) -> info.id) infos in
  let emitted = Hashtbl.create 64 and rows = ref [] in
  let first id = match Hashtbl.find_opt inputs id with
    | Some slots -> List.find_map Fun.id slots | None -> None in
  let rec emit_trunk id depth =
    (* The chain up the first inputs, stopping at a node already listed. *)
    let rec chain id acc =
      if Hashtbl.mem emitted id then Some id, acc
      else match first id with
        | Some source when Hashtbl.mem inputs source -> chain source (id :: acc)
        | _ -> None, id :: acc in
    let shared, nodes = chain id [] in
    Option.iter (fun id -> rows := (id, depth, true) :: !rows) shared;
    List.iter (fun id ->
      Hashtbl.replace emitted id ();
      rows := (id, depth, false) :: !rows;
      let primary_seen = ref false in
      List.iter (function
        | Some side when Hashtbl.mem inputs side ->
            if not !primary_seen then primary_seen := true
            else if Hashtbl.mem emitted side then
              rows := (side, depth + 1, true) :: !rows
            else emit_trunk side (depth + 1)
        | _ -> ()) (Option.value ~default:[] (Hashtbl.find_opt inputs id))) nodes in
  List.iter (fun id -> if not (Hashtbl.mem consumed id) then emit_trunk id 0) ids;
  Array.of_list (List.rev !rows)

let trunk_rows (network : Flow_sop.Network.t) ~viewed ~flags =
  Array.map (fun (id, depth, link) ->
    let node = Edit_graph.find network.Flow_sop.Network.geometry ~node_id:id in
    let label = match node with Some node -> Node.label node | None -> "" in
    let operation = match node with Some node -> Node.operation node | None -> "" in
    let details = [operation] @
      (if viewed = Some id then ["VIEW"] else []) @
      (if Edit_graph.is_bypassed network.geometry ~node_id:id then ["M"] else []) in
    { Pxui_shell.Tree.id; depth; link; ghost = false;
      label; detail = String.concat " · " details;
      badge = badge operation; flags = flags id node })
    (trunk network)

let rows value (network : Document.network) = match value.level with
  | Document.Scene -> scene_rows ?active:value.doc.active_camera network.graph.geometry,
      ["v"; "r"]
  | Inside id when kind value id = Some "geometry" ->
      trunk_rows network.graph ~viewed:network.displayed ~flags:(fun node_id node ->
        match node with Some _ -> [Some node_id = network.displayed] | None -> []), ["d"]
  | Inside _ ->
      trunk_rows network.graph ~viewed:None ~flags:(fun _ node ->
        match node with
        | Some node when Objects.has_flag "visible" node -> [Objects.flag "visible" node]
        | _ -> []),
      ["v"]

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
let apply_tree value (overlay, selection, tree, opened, label, rows) intent =
  let document = overlay.Flow_sop.Network.geometry in
  let module T = Pxui_shell.Tree in
  let world = match value.level with
    | Document.Inside id -> kind value id = Some "world"
    | Scene -> false in
  (* the nodes of a geometry object are the lowering of its graph: its list only selects *)
  let geometry = match value.level with
    | Document.Inside id -> kind value id = Some "geometry"
    | Scene -> false in
  let overlay = match intent with
    | Pxui_shell.Tree.Delete ids when not geometry ->
        Result.get_ok (Flow_sop.Network.remove_nodes ids overlay)
    | _ -> overlay in
  let stack () = Array.to_list rows
    |> List.filter_map (fun (row : T.row) -> if row.link then None else Some row.id) in
  let restacked order =
    let document = restack document order in
    document, selection, tree, opened, Some "Reorder layers", rows in
  let move_in order ids target drop =
    let rest = List.filter (fun id -> not (List.mem id ids)) order in
    List.concat_map (fun id ->
      if id <> target then [id]
      else match drop with
        | T.Before -> ids @ [id] | After | Inside -> id :: ids) rest in
  let document, selection, tree, opened, label, rows = match intent with
  | T.Select ids ->
      document, (match ids with
        | [] -> Selection.clear selection
        | ids -> Selection.select_nodes ids selection), tree, opened, label, rows
  | Flag _ when geometry ->
      (* the display node of a workspace graph is its result *)
      document, selection, tree, opened, label, rows
  | Flag { ids; column; value = on } ->
      let name = List.nth (if world then ["visible"] else ["visible"; "render"]) column in
      let document = List.fold_left (fun document id ->
          apply_parameter document id name (Parameter.Bool_value on)) document ids in
      document, selection, tree, opened, Some (if on then "Show" else "Hide"), rows
  | Move { ids; target; drop } when world ->
      restacked (move_in (stack ()) ids target drop)
  | Move { ids; target; drop } when value.level = Document.Scene ->
      let parent = match drop with
        | T.Inside -> Some target
        | Before | After -> Objects.parent document target in
      reparent document ids parent, selection, tree, opened, Some "Reparent", rows
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
       | None -> document, selection, tree, opened, label, rows
       | Some parent ->
           reparent document ids (Some parent), selection, tree, opened, Some "Reparent", rows)
  | Outdent ids when value.level = Document.Scene ->
      let document = List.fold_left (fun document id ->
          match Objects.parent document id with
          | Some parent -> reparent document [id] (Objects.parent document parent)
          | None -> document) document ids in
      document, selection, tree, opened, Some "Reparent", rows
  | Reorder { ids; delta } when world ->
      let order = stack () in
      (match List.find_index (fun id -> List.mem id ids) order with
       | Some index ->
           let target = List.nth_opt (List.filter (fun id -> not (List.mem id ids)) order)
               (max 0 (index + delta)) in
           (match target with
            | Some target -> restacked (move_in order ids target
                (if delta < 0 then T.Before else After))
            | None -> document, selection, tree, opened, label, rows)
       | None -> document, selection, tree, opened, label, rows)
  | Rename (id, name) when not geometry ->
      (match Option.map (Node.relabel name) (Edit_graph.find document ~node_id:id) with
       | Some node -> (match Edit_graph.replace_node node document with
         | Ok document -> document, selection, tree, opened, Some "Rename", rows
         | Error _ -> document, selection, tree, opened, label, rows)
       | None -> document, selection, tree, opened, label, rows)
  | Activate _ when geometry -> document, selection, tree, opened, label, rows
  | Activate id -> document, selection, tree, Some id, label, rows
  | Delete ids when not geometry ->
      let document = Edit_graph.remove_nodes ids document in
      document, Selection.clear selection, tree, opened, Some "Delete", rows
  | Rename _ | Delete _ | Move _ | Indent _ | Outdent _ | Reorder _ ->
      document, selection, tree, opened, label, rows

  in Result.get_ok (Doc.update_geometry (fun _ -> Ok document) overlay),
    selection, tree, opened, label, rows

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
  let has_scene = Editor_document.Contexts.graph_of workspace Flow.Workspace.Scene <> None in
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
  let has_world = Editor_document.Contexts.graph_of workspace Flow.Workspace.World <> None in
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
        scope_key = None; select_later = []; pane_graph = None; back = [];
        flow_catalog = lazy (Result.to_option (Editor_document.Contexts.catalog
          ~version:Flow_sop.Manifest.version factories));
        lisp_vocab = lazy (Lisp_text.vocab
          (List.map Flow_sop.Catalog.descriptor factories @ Editor_document.Contexts.descriptors));
        tree = Pxui_shell.Tree.create (); outline = Navigator.initial; held_keys = [];
        ui = (let ui = Pxui.Ui.create () in Pxui.Ui.set_font_size ui (default_text_size ()); ui); workspace;
        timeline = Sketch_support.Timeline.create (); cook;
        edit_error = None; status_fps = None;
        status_fps_at = Float.neg_infinity; last_dt = 0.; steady = 0;
        history = Editor_core.History.create doc;
        focus = Editor_core.Panels.main; focus_path = None; pane_keys = []; leader = Leader.Idle;
        keymap; timeline_frames = max 1 timeline_frames; queued = [];
        graph_at = None; graph_pane = None; graph_panes = [];
        list_at = None; text_at = None; outline_at = None; locals = [];
        started = { on = None; views = []; tabs = [] };
        carry = None; carry_budget; captions = []; traces = []; view_tools = None; gates = []; selected_box = None;
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

(* the open dialog, for the crash report *)
let prompt_name value = match value.prompt with
  | None -> "-" | Some Keys -> "keys" | Some (Saving _) -> "save preset" | Some (Palette _) -> "commands" | Some (Jumping _) -> "jump"
  | Some (Browsing _) -> "presets" | Some (Making_macro _) -> "make macro"

let level_name value = match value.level with
  | Document.Scene -> "scene"
  | Inside id -> "scene › " ^ Option.fold ~none:"?" ~some:Node.label
      (Edit_graph.find (scene value) ~node_id:id)

(* The strip while a payload is carried: what it is, then (a target hot) what putting it writes in
   the words of the text, or why the place refuses it. *)
let carry_line (c : _ carry) =
  let held = c.payload.value in
  let put = match c.via with `Keys -> "Enter" | `Pointer -> "release" in
  match c.preview with
  | Some (Showing { what; _ }) -> Printf.sprintf "Preview · %s writes %s · Esc drops" put what
  | Some (Held_back { what; reason; _ }) ->
      Printf.sprintf "Would write %s · no preview, %s · %s writes it" what reason put
  | Some (Refused { reason; _ }) -> "Refused · " ^ reason
  | None ->
      (match c.hint with Some hint -> hint ^ " · " | None -> "") ^
      (match c.via, c.targets with
       | `Pointer, _ -> Printf.sprintf "Carrying %s · put it on a place · Esc drops" held
       | `Keys, Some (_, (_ :: _ as targets)) ->
           Printf.sprintf "Carrying %s · put on %s · Enter writes · Esc drops" held
             (String.concat " · " (List.map (fun (letter, _, label) -> letter ^ " " ^ label) targets))
       | `Keys, _ ->
           Printf.sprintf "Carrying %s · nothing here takes it · u, i or Space j go elsewhere · Esc drops" held)

(* 2408 -> "2 408", the sheets' thousands *)
let group_thousands n =
  let digits = string_of_int n in
  let rec chop s = if String.length s <= 3 then [ s ]
    else String.sub s (String.length s - 3) 3 :: chop (String.sub s 0 (String.length s - 3)) in
  String.concat " " (List.rev (chop digits))

let status_text ?(brief = false) value =
  match value.carry with Some c -> carry_line c | None ->
  let cook = match Cook.status value.cook with
    | Async_cook.Cooking { seconds; queued = true; _ }
      when Sketch_support.Timeline.mode value.timeline = Sketch_support.Timeline.Playing ->
        (* playing and a newer frame is already waiting: frames are skipped *)
        Printf.sprintf "cook %d ms · skipping frames" (int_of_float (seconds *. 1000.))
    | Async_cook.Cooking { seconds; queued; _ } ->
        Printf.sprintf "Cooking… %.1fs%s" seconds
          (if queued then " · latest queued" else "")
    | Idle ->
        (match value.edit_error, value.cook.error, value.cook.seconds with
         | _ when projection value = Text_view && Text_pane.first_error value.text <> None ->
             "Text rejected: " ^ Flow.Diagnostic.to_string
               (Option.get (Text_pane.first_error value.text))
         | Some error, _, _ -> "Graph edit rejected: " ^ error
         | None, Some error, _ -> "Cook rejected: " ^ error
         | None, None, _ when value.notice <> None -> snd (Option.get value.notice)
         | None, None, Some seconds ->
             (match Flow_sop.Lower.status (snd value.doc.Document.workspace) ~seconds with
              | Some text -> text
              | None -> Printf.sprintf "checked · cooked %.3f s" seconds)
         | None, None, None -> "Waiting for first cook") in
  (* What the open level's keys do, so the World and the menu are findable. *)
  let hint = match value.level with
    | Document.Scene -> "i/double-click enter · Space a add · Space e World"
    | Inside id when kind value id = Some "world" ->
        "u up · drag map: move layer/sun · t dome/light · n reseed · d day cycle · [ ] time · Space m 3D/map"
    | Inside _ -> "u up · Space a add · Space l panel kind" in
  (if value.workspace.restored then "Default layout · Space z returns to the editor graph · " else "")
  ^ cook ^ (if brief then "" else " · " ^ level_name value ^ " · " ^ hint)

(* "ring · iteration 1 of 12": which iteration the viewport's highlight and the inspector show for the
   node selected in the graph pane (the innermost loop around it, or itself when it is one). *)
let probe_caption value = match value.scope_key, Pxui_graph.Scope.selected value.scope_view with
  | Some { scope; records = Some records; graph; _ }, [ path ] when graph_name value = Some graph ->
      let probe p = Option.value ~default:0 (Layout_by_path.Path_map.find_opt p value.probes) in
      let zones = List.filter (fun (n : Flow_sop.Projection.node) ->
        match n.zone with Some z -> z.kind <> Flow_sop.Projection.Let | None -> false)
        (Flow_sop.Projection.zones scope) in
      let own = List.find_opt (fun (n : Flow_sop.Projection.node) -> n.path = path) zones in
      let zone = match own with
        | Some n -> Some n.path
        | None -> (match Hashtbl.find_opt (Flow_sop.Probe.chains scope) path with
            | Some (_ :: _ as chain) -> Some (List.nth chain (List.length chain - 1))
            | _ -> None) in
      Option.bind zone (fun zone ->
        Option.map (fun count ->
          Printf.sprintf "%s · iteration %d of %d" (List.nth zone (List.length zone - 1)) (probe zone + 1) count)
          (List.assoc_opt zone (Flow_sop.Probe.counts records scope ~probe)))
  | _ -> None

(* The status strip under the view: kit text on the ground, under a hairline. *)
let status_box value ui (frame : Frame.t) ~render_status ~error_status ~context =
  let g = geometry value value.workspace frame in
  (* the pane really in use: the focus when a leaf of its kind is open, else the first leaf *)
  let focus = match List.exists (fun (l : Pxui_shell.Layout.leaf) -> Leader.scope l.panel = Leader.scope value.focus) g.leaves, g.leaves with
    | false, l :: _ -> l.panel | _ -> value.focus in
  let value = { value with focus } in
  let x, y, width, height = g.status_at in
  (* what every strip says first: the workspace, a dot for its state, then the layout in use *)
  let file = value.file in
  let state = if error_status <> None || value.edit_error <> None || value.cook.error <> None then `Error
    else match Cook.status value.cook with Async_cook.Cooking _ -> `Busy | Idle -> `Ok in
  let layout = match Option.bind value.doc.Document.shell (fun s -> s.switch) with
    | Some { layouts; active } when active < List.length layouts ->
        Printf.sprintf "layout %d \xc2\xb7 %s" active (Editor_core.Panels.summary (List.nth layouts active))
    | _ -> "" in
  let line = match error_status with Some error -> error | None ->
    status_text ~brief:true value ^ match render_status with None -> "" | Some status -> " \xc2\xb7 " ^ status in
  (* the focused pane's kind and what is selected: in the graph pane its node, in a viewport the
     object the brackets stand round *)
  let kind = match value.focus with Pxui_shell.Layout.View _ -> "Viewport" | panel -> Editor_core.Panels.name panel in
  let selection = match value.focus, value.selected_box with
    | Pxui_shell.Layout.View _, Some (_, _, name) -> Some name
    | _ ->
    match Pxui_graph.Scope.selected value.scope_view with
    | [ path ] -> List.nth_opt (List.rev path) 0
    | [] -> None
    | paths -> Some (Printf.sprintf "%d selected" (List.length paths)) in
  (* a panel being carried: its name in the accent, what the drag does, and how many windows float *)
  let moving = Option.bind value.workspace.window_live (fun (path, _) ->
    List.find_map (fun (l : Pxui_shell.Layout.leaf) ->
      if l.path = path then Some (Editor_core.Panels.name l.panel) else None) g.leaves) in
  let floating = List.length (List.filter (fun (l : Pxui_shell.Layout.leaf) -> l.floating) g.leaves) in
  let graphs = List.length (fst value.doc.Document.workspace).checked.graphs in
  (* the end follows the sheet's context: floating windows give their count alone; a graph that is
     the only docked pane (graph.html) gives its counts and zoom in place of layout and fps; any
     other layout keeps the layout summary and the frame rate *)
  let docked = List.filter (fun (l : Pxui_shell.Layout.leaf) -> not l.floating) g.leaves in
  let alone = floating = 0 && value.focus = Graph && List.length docked = 1 in
  let readout = if not alone then "" else
    let nodes = (Pxui_graph.Scope.stats value.scope_view).nodes in
    let selected = List.length (Pxui_graph.Scope.selected value.scope_view) in
    Printf.sprintf "%d node%s%s" nodes (if nodes = 1 then "" else "s")
      (if selected = 0 then "" else Printf.sprintf " \xc2\xb7 %d selected" selected) in
  let notes = if floating > 0 then [ Printf.sprintf "%d floating" floating ]
    else if alone then
      [ Printf.sprintf "zoom %d%%" (int_of_float (Float.round (100. *. Pxui_graph.Scope.zoom value.scope_view))) ]
    else match value.focus with
      | Pxui_shell.Layout.Outline -> [ Printf.sprintf "%d graph%s" graphs (if graphs = 1 then "" else "s") ]
      | _ -> [] in
  let layout, status_fps = if floating > 0 || alone then "", None else layout, value.status_fps in
  (* the keys each pane's sheet lists, as short labels; Lisp, Timeline and Inspector have none *)
  let jump = List.find_map (fun (c : Leader.command) ->
    if c.id = "scene.jump" then Option.map (fun t -> Editor_core.Keymap.label t, "jump") c.trigger else None) Leader.keymap in
  let extra = match value.focus with
    | Pxui_shell.Layout.Outline -> [ "/", "filter"; "i", "enter" ] @ Option.to_list jump
    | Graph -> [ "Tab", "add after"; "o", "open"; "v", "view"; "b", "bypass"; "i", "enter"; "f", "frame"; "w", "hints";
                 "Space", "leader" ]
    | View _ -> [ "w", "move"; "e", "rotate"; "r", "scale"; "i", "enter object"; "\xe2\x8c\xa5 drag", "orbit" ]
    | _ -> [] in
  if height <= 0 then false
  else if (match value.leader with Leader.Pending _ -> true | Idle -> false) then begin
    (* an open leader: the pending prefix in the accent and what the strip waits for *)
    let prefix = match value.leader with Leader.Pending p when p <> "" -> "Space " ^ p | _ -> "Space" in
    Pxui_shell.Status_bar.guide ui ~bounds:(x, y, width, height) ~file ~state ~layout ~readout ~text:line
      ?fps:status_fps ~notes ~leader:prefix ~context:Editor_core.Guide_context.Leader
      ([] : Leader.command list)
  end
  else if moving <> None then begin
    Pxui_shell.Status_bar.guide ui ~bounds:(x, y, width, height) ~file ~state ~layout ~readout ~text:line
      ?fps:status_fps ~notes ~accent:true ~kind:("moving " ^ Option.get moving)
      ~extra:[ "drag to an edge", "dock"; "Space o f", "float or dock"; "Space n", "new window" ]
      ~context:Editor_core.Guide_context.Canvas ([] : Leader.command list)
  end
  else if state <> `Error && value.carry = None && value.guide then begin
    Pxui_shell.Status_bar.guide ui ~bounds:(x, y, width, height) ~file ~state ~layout ~readout ~text:line
      ?fps:status_fps ~notes ~extra ~kind ?selection ~context ([] : Leader.command list)
  end
  else begin
    (* a refusal has the strip to itself: the whole message, up to the layout and frame rate *)
    let kind, selection = if state = `Error then None, None else Some kind, selection in
    Pxui_shell.Status_bar.draw ui ~bounds:(x, y, width, height) ~file ~state ~layout ~notes ~readout ?kind ?selection
      ~text:line ~fps:status_fps ();
    false
  end

(* Leader actions owned by the workspace; the environment handles the rest
   from [update.actions]. *)
let apply_action value (workspace, selection, tree, timeline, changes) action =
  let module T = Sketch_support.Timeline in
  let timeline_step step = let timeline, more = step timeline in
    workspace, selection, tree, timeline, changes @ more in
  let expand panel (workspace : shell) =
    { workspace with hidden = Pxui_shell.Layout.expand panel workspace.hidden } in
  match action with
  | Leader.Toggle_timeline | Toggle_graph | Toggle_inspector -> workspace, selection, tree, timeline, changes
  | Restore_layout ->
      (if workspace.restored then { workspace with restored = false; live = None; window_live = None }
       else { tree = Pxui_shell.Layout.default; hidden = [ Pxui_shell.Layout.Timeline ]; live = None; window_live = None;
              restored = true }), selection, tree, timeline, changes
  | Open_camera ->
      expand Pxui_shell.Layout.Inspector workspace,
      Selection.clear selection, tree, timeline, changes
  | Play_pause -> timeline_step T.toggle_pause
  | Reset -> timeline_step T.reset
  | Stop -> timeline_step T.stop
  | Add_node -> expand Pxui_shell.Layout.Graph workspace, selection, tree, timeline, changes
  | Frame_tile when projection value = List_view ->
      workspace, selection, Pxui_shell.Tree.reveal tree, timeline, changes
  | World_play when Sketch_support.Timeline.mode timeline <> Sketch_support.Timeline.Playing ->
      timeline_step T.toggle_pause
  | Frame_tile | Hide_ui | Look_through | Look_through_camera | Render_mode _ | Fly | Save_preset | Browse_presets | Save_source
  | Reload_source
  | List_command _ | Frame_camera | Undo | Redo | Command_palette
  | Guide_toggle | Guide_keys | Copy_lisp
  | Sketch_command _ | Scope_command _ | Toggle_map | Ui_scale _ | Enter | Up | Go_world
  | Panel_split _ | Panel_close | Panel_retype _ | Tool _
  | Layout_switch _ | Layout_new | Layout_remove | Window_new _ | Float_toggle | Peek | Pick_up | Jump
  | World_emit | World_reseed | World_time _ | World_play | World_preset _ ->
      workspace, selection, tree, timeline, changes

(* The undo label a graph intent gives its document change. *)
let intent_label = function
  | Dock_panels _ -> Some "Dock panel"
  | Panel_state (_, state) -> Some (if state.Editor_core.Panels.collapsed then "Collapse panel" else "Arrange panel")
  | Select_layout _ -> Some "Switch layout"
  | Syntax_edit op -> Some (Flow_sop.Flow_edit.label op)
  | Syntax_batch (label, _) -> Some label
  | Syntax_inline { make; _ } -> Some (Flow_sop.Flow_edit.label (make []))
  | Set_parameter { path; _ } -> Some ("Set " ^ path)
  | Object_arg _ -> Some "Edit expression"
  | Rename _ -> Some "Rename node"
  | Pin_row { pin; _ } -> Some (if pin = Some false then "Unpin row from card" else "Pin row to card")
  | Notice _ | Declined _ -> None

let in_world value = match value.level with
  | Document.Inside id -> kind value id = Some "world"
  | Scene -> false

(* World keys: edit the selected layer, or the World node in the scene. *)
let world_keys value (doc : Document.t) selection actions =
  let world_id = match value.level with Inside id -> Some id
    | Scene -> None in
  let edit_layer f label (doc, _) = match world_id, Selection.selected selection with
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

(* The ten digit commands take their labels from the layouts when which-key or the palette draws. *)
let layout_labels value keymap =
  let names = layouts value in
  List.filter_map (fun (command : Leader.command) -> match command.action with
    | Leader.Layout_switch i ->
        Option.map (fun (name, active) -> { command with Editor_core.Command.label =
          if active then name ^ " (active)" else name }) (List.nth_opt names i)
    | _ -> Some command) keymap

(* Commands that only mean something on this level and projection. *)
let routed value =
  let graph_shown = graph_family value in
  let listing = listing value and texting = texting value in
  List.filter (fun (command : Leader.command) -> match command.action with
    | List_command _ -> listing && graph_shown
    | Scope_command _ -> scope_name value <> None && graph_shown && not texting
    | Frame_tile -> not texting && graph_shown
        && (listing || command.trigger = Some (Editor_core.Keymap.Leader "f"))
    | Frame_camera -> List.exists (function _, Pxui_shell.Layout.View _ -> true | _ -> false)
        (Editor_core.Panels.leaves (shell_tree value value.workspace))
    (* Tab is the canvas's key for it; in the list Tab indents the row *)
    | Add_node -> not texting && (not listing || command.trigger = Some (Editor_core.Keymap.Leader "a"))
        && List.exists (fun (_, panel) -> panel = Pxui_shell.Layout.Graph)
        (Editor_core.Panels.leaves (shell_tree value value.workspace))
    | World_emit | World_reseed | World_time _ | World_play | World_preset _ ->
        in_world value
    | _ -> true) value.keymap |> layout_labels value

(* Every editor path records the same immutable document. No-op/rejected
   edits leave both the present and the merge state untouched. *)
let commit ?(label = "Edit") ?(merge = Editor_core.History.Step) doc history =
  if doc == Editor_core.History.present history then history
  else Editor_core.History.record ~label ~merge doc history

let parameter_gesture operation level id values =
  operation ^ "/" ^ level_key level ^ "/" ^ string_of_int id ^ "/"
  ^ String.concat "/" (List.sort_uniq String.compare (List.map fst values))

(* A workspace edit installed as the present: the source and its lowering are
   one history entry, the open level is re-resolved and the cook told about
   the new volatile nodes. *)
let install value doc ~label ~merge =
  let level = Document.resolve_level doc value.level in
  let value' = { value with doc; level; workspace = unrestore value.doc doc value.workspace } in
  Cook.set_volatile value.cook (Flow_sop.Lower.is_volatile (snd doc.workspace));
  { value' with history = commit ~label ~merge doc value.history;
    selection = if level = value.level then value.selection else Selection.empty }

(* The text pane's applies (plan W7): the whole workspace text, or one
   binding's expression; atomic, one history entry "Edit text". *)
let text_edit ?(label = "Edit text") ?(merge = Editor_core.History.Step) value text =
  Result.map (fun doc -> install value doc ~label ~merge)
    (Doc.text_edit ~factories:value.factories value.doc text)

(* Selection patches root bindings into one candidate graph, checked and
   installed once. Omitted bindings stay and the shown result cannot change.
   Without a closure the tab shows the graph form, replaced whole. *)
let binding_edit ?(merge = Editor_core.History.Step) value path text =
  let at_line_1 (d : Flow.Diagnostic.t) = { d with position = Some { line = 1; col = 0 }; span = None } in
  let ws, _ = value.doc.Document.workspace in
  match Text_pane.graph_op ws.source ~graph:(List.hd path) ~selection:path text with
  | Error d -> Error [ (if d.position = None then at_line_1 d else d) ]
  | Ok op ->
      (match Doc.syntax_edit_result ~factories:value.factories value.doc op with
       | Ok doc -> Ok (install value doc ~label:"Edit text" ~merge)
       | Error d -> Error [ at_line_1 d ])

(* The Graph tab's apply: the draft must be the one graph (or function) form, which replaces the
   graph's; atomic like every apply. *)
let graph_edit ?(merge = Editor_core.History.Step) value name text =
  let ws, _ = value.doc.Document.workspace in
  match Text_pane.graph_op ws.source ~graph:name text with
  | Error d ->
      Error [ (if d.position = None then { d with position = Some { line = 1; col = 0 } } else d) ]
  | Ok op ->
      (match Doc.syntax_edit_result ~factories:value.factories value.doc op with
       | Ok doc -> Ok (install value doc ~label:"Edit text" ~merge)
       | Error d -> Error [ { d with position = Some { line = 1; col = 0 }; span = None } ])

(* Fold the pane's intents: drafts live in [value.text] (view state); a
   refused apply keeps the draft and its errors and changes nothing else. *)
let scrub_merge = Editor_core.History.Gesture "text-scrub"

let apply_text value intents =
  List.fold_left (fun value intent ->
    let text = value.text in
    let with_text text = { value with text } in
    let workspace = fst value.doc.Document.workspace in
    let base old = Some (Option.value ~default:workspace old) in
    (* a draft begun on an older document: merged with what changed since on the syntax tree
       ({!Text_pane.merge3}); only a value both changed keeps the draft as a conflict *)
    let checked ?(metadata = false) ~shown ~draft old apply =
      match old with
      | Some (previous : Editor_document.Workspace_doc.t) when previous.source != workspace.source
          || (metadata && (previous.layout != workspace.layout || previous.settings != workspace.settings)) ->
          (match Text_pane.merge3 ~base:(shown previous) ~mine:draft ~theirs:(shown workspace) with
           | Some merged -> apply merged
           | None ->
               Error [Flow.Diagnostic.error ~position:{line = 1; col = 0} ~code:"E_DRAFT_CONFLICT"
                 "The document changed in the same place as this draft. Your draft is kept; discard it and reapply your edits to the current text."])
      | _ -> apply draft in
    let whole = Editor_document.Workspace_doc.to_text in
    let of_graph graph (ws : Editor_document.Workspace_doc.t) =
      (Text_pane.make_shown ws.source graph None Text_pane.Graph).text in
    let of_binding path (ws : Editor_document.Workspace_doc.t) =
      (Text_pane.make_shown ws.source (List.hd path) (Some path) Text_pane.Selection).text in
    match intent with
    | Text_pane.Tab tab -> with_text { text with tab }
    | Menu menu -> with_text { text with menu }
    | Toggle_wrap -> with_text { text with wrap = not text.wrap }
    | Toggle_parinfer -> with_text { text with parinfer = not text.parinfer }
    | Picker picker -> with_text { text with picker }
    | Open_graph graph -> go value graph
    | Select_binding path ->
        { value with scope_view = Pxui_graph.Scope.select [ path ] value.scope_view }
    | Carry_over _ -> value  (* read by the carry's report, not an edit *)
    | Doc_draft draft -> with_text { text with draft = Some draft; doc_base = base text.doc_base; doc_errors = [] }
    | Doc_discard -> with_text { text with draft = None; doc_base = None; doc_errors = [] }
    | Doc_apply draft ->
        (match checked ~metadata:true ~shown:whole ~draft text.doc_base (text_edit value) with
         | Ok value -> { value with text = { text with draft = None; doc_base = None; doc_errors = [] } }
         | Error doc_errors -> with_text { text with draft = Some draft; doc_base = base text.doc_base; doc_errors })
    | Binding_draft (path, draft) ->
        with_text { text with binding_draft = Some (path, draft); binding_base = base (match text.binding_draft with Some (old, _) when old = path -> text.binding_base | _ -> None); binding_errors = [] }
    | Binding_discard -> with_text { text with binding_draft = None; binding_base = None; binding_errors = [] }
    | Graph_draft (graph, draft) ->
        with_text { text with graph_draft = Some (graph, draft); graph_base = base (match text.graph_draft with Some (old, _) when old = graph -> text.graph_base | _ -> None); graph_errors = [] }
    | Graph_discard -> with_text { text with graph_draft = None; graph_base = None; graph_errors = [] }
    | Graph_apply (graph, draft) ->
        (match checked ~shown:(of_graph graph) ~draft text.graph_base (graph_edit value graph) with
         | Ok value -> { value with text = { text with graph_draft = None; graph_base = None; graph_errors = [] } }
         | Error graph_errors -> with_text { text with graph_draft = Some (graph, draft); graph_base = base text.graph_base; graph_errors })
    | Binding_apply (path, draft) ->
        (match checked ~shown:(of_binding path) ~draft text.binding_base (binding_edit value path) with
         | Ok value -> { value with text = { text with binding_draft = None; binding_base = None; binding_errors = [] } }
         | Error binding_errors ->
             with_text { text with binding_draft = Some (path, draft); binding_base = base text.binding_base; binding_errors })
    (* a dragged number: the text applies on every frame of the drag as one "Edit text" entry
       (the gesture seals on release); the draft stays until the drag ends so the editor keeps
       the text it is dragging in *)
    | Doc_scrub (draft, done_) ->
        (match checked ~metadata:true ~shown:whole ~draft text.doc_base (text_edit ~merge:scrub_merge value) with
         | Ok value -> { value with text = { text with draft = (if done_ then None else Some draft); doc_base = (if done_ then None else Some (fst value.doc.workspace)); doc_errors = [] } }
         | Error doc_errors -> with_text { text with draft = Some draft; doc_base = base text.doc_base; doc_errors })
    | Graph_scrub (graph, draft, done_) ->
        (match checked ~shown:(of_graph graph) ~draft text.graph_base (graph_edit ~merge:scrub_merge value graph) with
         | Ok value -> { value with text = { text with graph_draft = (if done_ then None else Some (graph, draft)); graph_base = (if done_ then None else Some (fst value.doc.workspace)); graph_errors = [] } }
         | Error graph_errors -> with_text { text with graph_draft = Some (graph, draft); graph_base = base text.graph_base; graph_errors })
    | Binding_scrub (path, draft, done_) ->
        (match checked ~shown:(of_binding path) ~draft text.binding_base (binding_edit ~merge:scrub_merge value path) with
         | Ok value -> { value with text = { text with binding_draft = (if done_ then None else Some (path, draft)); binding_base = (if done_ then None else Some (fst value.doc.workspace)); binding_errors = [] } }
         | Error binding_errors -> with_text { text with binding_draft = Some (path, draft); binding_base = base text.binding_base; binding_errors })) value intents

(* The intents of a text pane that is not the one in use fold into its own state. *)
let apply_text_at value key intents =
  if intents = [] then value else
  let mine = value.text in
  let v = apply_text { value with text = (local_of value key).code } intents in
  { v with text = mine; locals = put_local key (fun l -> { l with code = v.text }) v.locals }

(* The unapplied drafts of a text pane, as the applies its Check & apply would make. *)
let draft_applies ?except (text : Text_pane.state) =
  (match text.draft with Some d when Some d <> except -> [ Text_pane.Doc_apply d ] | _ -> [])
  @ (match text.graph_draft with Some (g, d) -> [ Text_pane.Graph_apply (g, d) ] | None -> [])
  @ (match text.binding_draft with Some (p, d) -> [ Text_pane.Binding_apply (p, d) ] | None -> [])

(* Some text pane holds text that is not in the document ([except]: the text of a refused
   reload, which is the file's and not the user's). *)
let has_draft ?except value =
  draft_applies ?except value.text <> []
  || List.exists (fun (_, (l : local)) -> draft_applies ?except l.code <> []) value.locals

(* What Command-S writes: the workspace text and, without a settings graph, the settings. *)
let same_text (a : Document.t) (b : Document.t) =
  fst a.workspace == fst b.workspace && a.settings == b.settings

(* Work a reload of the source file would lose: edits since the file's text, or a draft. *)
let unsaved ?except value = not (same_text value.doc value.filed) || has_draft ?except value

(* The document is the file's text now (saved over it). *)
let filed value = { value with filed = value.doc }

(* Command-S with a draft: every draft is applied first (each one its "Edit text" entry); a draft
   that does not check stays with its errors, and [Error] says the save must wait. *)
let apply_drafts ?except value =
  let value = apply_text value (draft_applies ?except value.text) in
  let value = List.fold_left (fun v (key, (l : local)) -> apply_text_at v key (draft_applies ?except l.code))
    value value.locals in
  if has_draft ?except value then Error value else Ok value


(* A panel header's title: its type, and where a looped panel comes from (register E1). *)
let panel_title value (leaf : Pxui_shell.Layout.leaf) =
  (* a graph panel's title is its own pane's *)
  let value = shown_as value (panel_key value.doc leaf.path, leaf.path, leaf.panel) in
  let graph = Option.value ~default:"" (graph_name value) in
  let name, sub = match leaf.panel with
    | View _ -> "Viewport",
        (* the scene it shows and its render camera: "scene / camera" *)
        let scene_name =
          Option.value ~default:"" (List.find_map (fun (g : Flow.Workspace.graph) ->
            if g.context = Flow.Workspace.Scene then Some g.name else None)
            (fst value.doc.Document.workspace).checked.graphs) in
        let camera = Option.bind value.doc.Document.active_camera (fun id ->
          Option.map Node.label (Edit_graph.find (scene value) ~node_id:id)) in
        String.concat " / " (List.filter (( <> ) "") [ scene_name; Option.value ~default:"" camera ])
    | Graph -> "Graph", if graph = "" then "" else
        let context = List.find_map (fun (g : Flow.Workspace.graph) ->
          if g.name = graph then Some (Flow.Workspace.context_name g.context) else None)
          (fst value.doc.Document.workspace).checked.graphs in
        (if value.back = [] then graph
         else String.concat " / " (List.map String.trim (String.split_on_char '>' (route value))))
        ^ Option.fold ~none:"" ~some:(fun c -> " / " ^ c) context
    | List -> "List", level_name value
    | Lisp -> "Lisp", if (let _, _, w, _ = leaf.frame in w < 400) then ""  (* the narrow sheet has the kind alone *)
        else if graph = "" then value.file else if value.file = "" then graph else value.file ^ " / " ^ graph
    | Inspector -> "Inspector", (match (if value.scope_key = None then [] else Pxui_graph.Scope.selected value.scope_view) with
        | [ path ] when graph <> "" ->
            (* the node's title (a result is `result`, not `@result`); the narrow column has the node alone *)
            let title = match Option.bind value.scope_key (fun (k : scope_key) -> Flow_sop.Projection.find k.scope path) with
              | Some n -> Flow_sop.Projection.title n
              | None -> List.nth path (List.length path - 1) in
            if (let _, _, w, _ = leaf.frame in w < 340) then title else graph ^ " / " ^ title
        | _ -> graph)
    | Outline -> "Outline", if (let _, _, w, _ = leaf.frame in w < 300) then ""  (* the narrow sheet has the kind alone *)
        else value.file
    | Timeline -> "Timeline",
        (* the real step of the sketch: the same step every frame is a fixed one *)
        if value.steady >= 3 && value.last_dt > 0. then Printf.sprintf "fixed dt 1/%d" (int_of_float (Float.round (1. /. value.last_dt)))
        else "realtime" in
  let name = if sub = "" then name else name ^ "\t" ^ sub in
  match Option.bind value.doc.Document.shell (fun s ->
      if value.workspace.restored then None else List.assoc_opt leaf.path s.origins) with
  | Some (Document.Loop (from, _)) -> name ^ " · from loop " ^ Document.describe (fst value.doc.Document.workspace).source from
  | _ -> name

(* Make a reusable function from the selected nodes: the names they read from outside are typed from the
   graph pane's projection, the context is the result's (a geometry is [sop], anything else [value]). *)
let defn_change value paths =
  let ws, _ = value.doc.Document.workspace in
  let scope = Option.map (fun (k : scope_key) -> k.scope) value.scope_key in
  let rec ty_text : Flow.Ty.t -> string option = function
    | Geometry -> Some "geometry" | Float -> Some "float" | Int -> Some "int" | Bool -> Some "bool"
    | Vec3 -> Some "vec3" | Text -> Some "text" | Fn -> Some "fn"
    | List t -> Option.map (fun s -> "(list " ^ s ^ ")") (ty_text t)
    | _ -> None in
  let rec find_ty name (s : Flow_sop.Projection.scope) =
    match List.find_opt (fun (i : Flow_sop.Projection.input) -> i.name = name) s.inputs with
    | Some i -> Some i.ty
    | None -> List.find_map (fun (n : Flow_sop.Projection.node) ->
        if List.mem name n.binds then Some n.ty
        else Option.bind n.zone (fun (z : Flow_sop.Projection.zone) -> find_ty name z.scope)) s.nodes in
  match Flow_sop.Flow_edit.defn_draft ws.source paths, scope with
  | Error d, _ -> Declined d.Flow.Diagnostic.message
  | Ok _, None -> Declined "Open a graph to make a function from its nodes"
  | Ok draft, Some scope ->
      let typed = List.map (fun n -> n, Option.bind (find_ty n scope) ty_text) draft.free in
      (match List.find_opt (fun (_, t) -> t = None) typed with
       | Some (n, _) -> Declined (Printf.sprintf "The function reads %s, whose type a function cannot take." n)
       | None ->
           let result_ty = List.fold_left (fun acc path ->
             match Flow_sop.Projection.find scope path with Some n -> Some n.ty | None -> acc) None paths in
           Syntax_edit (Flow_sop.Flow_edit.Make_defn { nodes = paths; name = draft.name;
             context = (if result_ty = Some Flow.Ty.Geometry then "sop" else "value");
             params = List.map (fun (n, t) -> n, Option.get t) typed }))

(* The Navigator: what it shows of the document (see {!Navigator}). *)
(* The scene's objects as the Outline lists them: the list panel's rows, with what each is and
   the binding that places it. *)
let outline_objects value : Navigator.obj list =
  let document = scene value in
  let selected = if value.level = Document.Scene then Selection.selected_nodes value.selection else [] in
  Array.to_list (scene_rows document) |> List.map (fun (row : Pxui_shell.Tree.row) ->
    let node = Edit_graph.find document ~node_id:row.id in
    let flag name = Option.bind node (fun node ->
      if Objects.has_flag name node then Some (Objects.flag name node) else None) in
    let lead = value.doc.Document.active_camera = Some row.id in
    (* a light says its shape, the render camera that it is active *)
    let choice = Option.bind node (fun node -> List.find_map (fun (f : Parameter.field_view) ->
      match f.name, f.current with
      | ("shape" | "type"), Parameter.Choice_value v -> Some (String.lowercase_ascii v) | _ -> None)
      (Node.parameter_fields node)) in
    let operation = Option.map Node.operation node in
    let field name = Option.bind node (fun node -> List.find_map (fun (f : Parameter.field_view) ->
      match f.name = name, f.current with
      | true, Parameter.Float_value v -> Some v | _ -> None) (Node.parameter_fields node)) in
    (* the sheet's words: a camera its focal length, a geometry object the graph it references, the
       World a reference to its graph; a light its shape *)
    let name, detail = match operation with
      | Some "camera" ->
          row.label, (match field "fov" with
            | Some fov when fov > 0. && fov < 180. ->
                Printf.sprintf "%.0f mm" (12. /. Float.tan (fov *. Float.pi /. 360.))
            | _ -> row.detail)
      | Some "geometry" ->
          row.label, (match graph_of_object value row.id with Some graph -> "ref " ^ graph | None -> row.detail)
      | Some "world" -> "world", "ref " ^ row.label
      | _ -> row.label, Option.value choice ~default:row.detail in
    (* the render camera's mark is its flag (the accent); the World renders while it is in the scene;
       neither is a field a press can write *)
    let inert, render = match operation with
      | Some "camera" -> true, Some lead
      | Some "world" -> true, Some true
      | _ -> false, flag "render" in
    (* the render camera has both flags, its visible one only showing *)
    let visible = match operation with Some "camera" -> Some true | _ -> flag "visible" in
    let rank = match operation with Some "camera" -> 0 | Some "light" -> 1 | Some "world" -> 4 | _ -> 2 in
    rank, { Navigator.depth = row.depth; letter = fst row.badge; name; detail;
      visible; render; lead; inert; chosen = List.mem row.id selected;
      home = (match List.assoc_opt row.id value.doc.Document.homes.objects with
        | Some (Document.Bound_at path) -> Some path | _ -> None) }) |> fun rows ->
  (* the sheet's order: the camera, the lights, the geometry, the World; a nested scene keeps its tree *)
  if List.for_all (fun (_, (o : Navigator.obj)) -> o.depth = 0) rows
  then List.map snd (List.stable_sort (fun (a, _) (b, _) -> compare a b) rows)
  else List.map snd rows

let navigator_params value : Navigator.params =
  let ws = fst value.doc.Document.workspace in
  let active = graph_name value in
  let here = match value.scope_key, active with
    | Some k, Some name when k.graph = name -> Some k | _ -> None in
  { workspace = ws.checked; active;
    scope = Option.map (fun (k : scope_key) -> k.scope) here;
    records = Option.bind here (fun (k : scope_key) -> k.records);
    probes = (fun p -> Option.value ~default:0 (Layout_by_path.Path_map.find_opt p value.probes));
    selected = Pxui_graph.Scope.selected value.scope_view;
    chips = (match value.scope_key with
      | Some { evaluated = Some ev; _ } -> Navigator.chips ev
      | _ -> []);
    notes = (match value.scope_key with
      | Some { evaluated = Some ev; _ } -> Navigator.notes ev
      | _ -> []);
    objects = outline_objects value;
    root_detail = Printf.sprintf "%d spp" (Objects.Root.render value.doc.Document.root).max_spp;
    layouts = Option.map (fun (sw : Document.switch) -> List.map Editor_core.Panels.summary sw.layouts, sw.active)
      (Option.bind value.doc.Document.shell (fun s -> s.switch)) }

(* The leaf the graph pane in use draws in, when it is open. *)
let graph_leaf value (g : Pxui_shell.Layout.geometry) =
  Option.bind (graph_path value) (fun path ->
    List.find_opt (fun (l : Pxui_shell.Layout.leaf) ->
      l.path = path && l.panel = Graph && (let _, _, _, h = l.body in h > 0)) g.leaves)

(* Chrome emits document edits; splitter drafts stay local until release. A
   refused structural edit returns a notice and preserves the document. *)
(* The focused leaf: the one clicked when its kind is shown twice, else the first of its kind. *)
let focused_leaf (g : Pxui_shell.Layout.geometry) focus path =
  match List.find_opt (fun (l : Pxui_shell.Layout.leaf) -> Some l.path = path && l.panel = focus) g.leaves with
  | Some leaf -> Some leaf
  | None ->
      (* the tree changed under the focus: a split moves the leaf a level down (and a viewport's
         key follows its path), a retype leaves another kind at the path.  The leaf of that kind
         under the old path, else the leaf now at the path, else the first of the kind. *)
      let kind (l : Pxui_shell.Layout.leaf) = Leader.scope l.panel = Leader.scope focus in
      let rec under prefix path = match prefix, path with
        | [], _ -> true | a :: p, b :: q -> a = b && under p q | _ :: _, [] -> false in
      let first f = List.find_opt f g.leaves in
      let ( <|> ) a b = match a with Some _ -> a | None -> b () in
      Option.bind path (fun p -> first (fun l -> kind l && under p l.path))
      <|> (fun () -> first (fun l -> Some l.path = path))
      <|> (fun () -> Pxui_shell.Layout.find g focus)
      <|> (fun () -> first kind)
      (* its panel was closed and no other is of its kind: the leaf that shares the most of its
         path, the neighbour that took its place *)
      <|> (fun () -> Option.bind path (fun p ->
        let rec shared a b = match a, b with x :: a, y :: b when x = y -> 1 + shared a b | _ -> 0 in
        List.fold_left (fun best (l : Pxui_shell.Layout.leaf) -> match best with
          | Some (b : Pxui_shell.Layout.leaf) when shared p b.path >= shared p l.path -> best
          | _ -> Some l) None g.leaves))

let panel_kind : Pxui_shell.Layout.panel -> string = function
  | View _ -> "viewport" | Graph -> "graph" | List -> "list" | Lisp -> "lisp"
  | Inspector -> "inspector" | Outline -> "outline" | Timeline -> "timeline"

(* Space [ and Space n: the layouts of the switch and the floating windows, each one edit of the
   editor graph (written from the layout shown first, when the document has none). *)
let layout_actions value (workspace : shell) ~(leaf : Pxui_shell.Layout.leaf option) actions =
  let graph = Option.map (fun (g : Flow.Workspace.graph) -> g.name)
    (Workspace_doc.editor_graph (fst value.doc.Document.workspace)) in
  let edit make = match graph with
    | _ when workspace.restored ->
        [ Declined "The default layout is showing. Space z returns to the editor graph." ]
    | Some graph -> [ Syntax_edit (make graph) ]
    | None ->
        let scene = Option.value ~default:"scene" (List.find_map (fun (g : Flow.Workspace.graph) ->
          if g.context = Flow.Workspace.Scene then Some g.name else None)
          (fst value.doc.Document.workspace).checked.graphs) in
        let text, _ = Bars.tree_text ~name:"editor" ~scene (shell_tree value { workspace with live = None }) in
        (match Flow.Syntax.parse text with
         | Ok [ form ] -> [ Syntax_batch (Flow_sop.Flow_edit.label (make "editor"),
             [ Flow_sop.Flow_edit.Set_graph { name = "editor"; form }; make "editor" ]) ]
         | _ -> [ Declined "The layout could not be written as an editor graph." ]) in
  List.concat_map (function
    | Leader.Layout_switch index when Option.is_some (Option.bind value.doc.Document.shell (fun s -> s.switch)) ->
        edit (fun graph -> Flow_sop.Flow_edit.Set_layout { graph; index })
    | Layout_switch index -> (* an older file: several editor graphs *)
        (match List.nth_opt (layouts value) index with Some (name, _) -> [ Select_layout name ] | None -> [])
    | Layout_new when Option.is_none (Option.bind value.doc.Document.shell (fun s -> s.switch))
                      && layouts value <> [] ->
        (* an older file with several editor graphs: they become the layouts of one switch first *)
        (match graph with
         | Some graph -> [ Syntax_batch ("Merge layouts", [ Flow_sop.Flow_edit.Merge_layouts { graph };
                                                            Flow_sop.Flow_edit.Layout_new { graph } ]) ]
         | None -> [])
    | Layout_new -> edit (fun graph -> Flow_sop.Flow_edit.Layout_new { graph })
    | Layout_remove -> edit (fun graph -> Flow_sop.Flow_edit.Layout_remove { graph })
    | Window_new panel -> edit (fun graph -> Flow_sop.Flow_edit.Layout_window { graph; kind = panel_kind panel })
    | Peek ->
        (match peek_target value with
         | Some target -> edit (fun graph -> Flow_sop.Flow_edit.Layout_window { graph; kind = "graph:" ^ target })
         | None -> [ Declined "Nothing selected to peek at" ])
    | Float_toggle ->
        (match leaf with
         | Some leaf -> edit (fun graph -> Flow_sop.Flow_edit.Layout_float { graph; at = leaf.path })
         | None -> [])
    | _ -> []) actions

let layout_intents value (workspace : shell) intents =
  let base = shell_tree value { workspace with live = None } in
  let editor = Option.map (fun (g : Flow.Workspace.graph) -> g.name)
    (Workspace_doc.editor_graph (fst value.doc.Document.workspace)) in
  let shell = if workspace.restored then None else value.doc.Document.shell in
  let edit path make = match editor, shell with
    | Some graph, Some s ->
        (match List.assoc_opt path s.origins with
         | Some (Document.Bound name) -> [ Syntax_edit (make [ graph; name ]) ]
         | Some (Inline (home, key)) -> [ Syntax_inline { home; key; make } ]
         | Some (Loop (home, key)) ->
             (* a loop's panels are copies of its one template: retyping edits the template *)
             (match make [] with
              | Flow_sop.Flow_edit.Set_panel_kind { kind; _ } ->
                  [ Syntax_inline { home; key; make = (fun p ->
                      Flow_sop.Flow_edit.Set_panel_kind { node = p @ [ "@result" ]; kind }) } ]
              | _ -> [ Declined ("These panels are copies made by a loop in " ^ Document.describe (fst value.doc.Document.workspace).source home
                  ^ ": retype them (Space o), or edit the loop in the editor graph.") ])
         | None -> [ Declined "This panel is not part of the editor graph's tree." ])
    | _ when workspace.restored ->
        [ Declined "The default layout is showing. Space z returns to the editor graph." ]
    | _ ->
        (* no editor graph: the layout shown is written as one first, then edited *)
        let scene = Option.value ~default:"scene" (List.find_map (fun (g : Flow.Workspace.graph) ->
          if g.context = Flow.Workspace.Scene then Some g.name else None)
          (fst value.doc.Document.workspace).checked.graphs) in
        let text, name_of = Bars.tree_text ~name:"editor" ~scene base in
        (match Flow.Syntax.parse text, name_of path with
         | Ok [ form ], Some leaf ->
             [ Syntax_edit (Flow_sop.Flow_edit.Set_graph { name = "editor"; form });
               Syntax_edit (make [ "editor"; leaf ]) ]
         | _ -> [ Declined "This panel is not part of the layout." ]) in
  let kind = panel_kind in
  let save_state path state =
    let prefix = if editor <> None then [] else
      let scene = Option.value ~default:"scene" (List.find_map (fun (g : Flow.Workspace.graph) ->
        if g.context = Flow.Workspace.Scene then Some g.name else None)
        (fst value.doc.Document.workspace).checked.graphs) in
      let text, _ = Bars.tree_text ~name:"editor" ~scene base in
      match Flow.Syntax.parse text with
      | Ok [form] -> [Syntax_edit (Flow_sop.Flow_edit.Set_graph {name = "editor"; form})]
      | _ -> [] in
    prefix @ [Panel_state (path, state)] in
  List.fold_left (fun ((w : shell), changes) -> function
    | Pxui_shell.Chrome.Toggle path ->
        let state = panel_state value path in
        w, changes @ save_state path { state with collapsed = not state.collapsed }
    | Window (path, window) ->
        w, changes @ save_state path { (panel_state value path) with window }
    | Window_drag (path, window, released) ->
        if released then { w with window_live = None },
          changes @ save_state path { (panel_state value path) with window = Some window }
        else { w with window_live = Some (path, window) }, changes
    | Dragging _ -> w, changes
    | Dock_panel (source, target, side) -> w, changes @ [Dock_panels (source, target, side)]
    | Resize { node; size } -> { w with live = Some (node, size) }, changes
    | Settled ->
        (match w.live with
         | None -> w, changes
         | Some (node, size) ->
             let w = { w with live = None } in
             w, changes @ edit node (fun node -> Flow_sop.Flow_edit.Set_layout_size { node; size }))
    | Split_panel (path, axis) ->
        w, changes @ edit path (fun node -> Flow_sop.Flow_edit.Split_panel { node; axis })
    | Close_panel path ->
        w, changes @ edit path (fun node -> Flow_sop.Flow_edit.Close_panel { node })
    | Retype_panel (path, panel) ->
        w, changes @ edit path (fun node ->
          Flow_sop.Flow_edit.Set_panel_kind { node; kind = kind panel }))
    (workspace, []) intents

let dock_panels ~factories (doc : Document.t) source target side =
  let ( let* ) = Result.bind in
  let states = (fst doc.workspace).layout.panels in
  let source_key = panel_key doc source and target_key = panel_key doc target in
  let saved key = Option.value ~default:Editor_core.Panels.default_state (Layout_by_path.Path_map.find_opt key states) in
  let bind doc path = Doc.panel_node ~factories
    ~loop_message:"These panels are copies made by a loop: move their tile in the editor graph." doc path in
  let* doc, node = bind doc source in
  let* doc, target = bind doc target in
  let* doc = Doc.syntax_edit ~factories doc (Flow_sop.Flow_edit.Dock_panel {node; target; side}) in
  let copy_pos = if side = `Left || side = `Top then 3 else 2 in
  let copy = match Flow_sop.Flow_edit.arg_text (fst doc.workspace).source target (Pos copy_pos) with
    | Some {Flow.Syntax.node = Sym name; _} -> List.rev (name :: List.tl (List.rev target))
    | _ -> target in
  Ok (Doc.layout_edit doc (fun layout ->
    let panels = layout.panels |> Layout_by_path.Path_map.remove source_key
      |> Layout_by_path.Path_map.remove target_key
      |> Layout_by_path.Path_map.add node { (saved source_key) with window = None }
      |> Layout_by_path.Path_map.add copy (saved target_key) in
    { layout with panels }))

(* A pane's request applied to the open network: an object's parameter or name.  Text gestures
   ([Syntax_edit]) are applied to the whole document afterwards. *)
let apply_change (document, error, effects) = function
  | Set_parameter { node; path; value } ->
      (match Doc.apply_parameters document ~node_id:node [ path, value ] with
       | Error message -> document, Some message, effects
       | Ok (document, changed) -> document, None, Parameter.union_effects effects changed)
  | Rename { node; label } ->
      (match Doc.relabel document ~node_id:node label with
       | Error message -> document, Some message, effects
       | Ok document -> document, None, effects)
  | Syntax_edit _ | Syntax_batch _ | Syntax_inline _ | Select_layout _ | Panel_state _ | Dock_panels _ | Object_arg _ | Pin_row _ | Notice _ | Declined _ -> document, error, effects

(* Command-C / X: the selected bindings as Lisp pairs ("name expr" per line) on the clipboard,
   the text a let* vector or the Lisp pane takes. *)
let copy_bindings value paths =
  let ws, _ = value.doc.Document.workspace in
  let lines = List.filter_map (fun path -> match Text_pane.binding ws.source path with
    | Some (_, v) -> Some (List.nth path (List.length path - 1) ^ " " ^ String.trim (fst (Flow.Lisp.print [ v ])))
    | None -> None) paths in
  match lines with
  | [] -> Declined "Nothing to copy"
  | lines ->
      (match Clipboard.set_text (String.concat "\n" lines) with
       | Ok () -> Notice (Printf.sprintf "Copied %d binding%s" (List.length lines) (if List.length lines = 1 then "" else "s"))
       | Error message -> Declined ("Clipboard: " ^ message))

(* The palette's "Copy workspace as Lisp": the text Command-S writes, on the clipboard. *)
let copy_workspace value =
  match Clipboard.set_text (Preset.text value.doc) with
  | Ok () -> Info, "Copied the workspace as Lisp"
  | Error message -> Refusal, "Clipboard: " ^ message

(* Command-V: the clipboard's "name expr" pairs (or bare expressions, named by their head) become
   [Add_node]s in the selected scope ({!Text_pane.paste_ops}), one history entry. *)
let paste_bindings value =
  match add_target value, Clipboard.get_text () with
  | None, _ -> [ Declined "Open a graph to paste into" ]
  | Some _, Error message -> [ Declined ("Clipboard: " ^ message) ]
  | Some (graph, _), Ok text ->
      let ws, _ = value.doc.Document.workspace in
      let scope = match Pxui_graph.Scope.selected value.scope_view with
        | [ path ] when List.length path >= 2 -> List.filteri (fun i _ -> i < List.length path - 1) path
        | _ -> [ graph ] in
      (* one gesture: every binding lands or none does *)
      (match Text_pane.paste_ops ws.source ~graph ~scope text with
       | Error message -> [ Declined message ]
       | Ok [ op ] -> [ Syntax_edit op ]
       | Ok ops -> [ Syntax_batch ("Paste", ops) ])

(* What the add menu of a scene adds beside the object kinds: the World, a merge, and the
   geometry of each SOP graph (a second object over a graph that already exists) *)
let scene_entries value =
  let entry key label category =
    { Pxui_graph.Node_menu.key; label; category; arity = 0; context = "scene"; output = Flow.Ty.Geometry;
      off = None } in
  entry "world" "World" [ "Object" ] :: entry "merge" "Merge" [ "Object" ]
  :: entry "material" "Material" [ "Material" ]
  :: List.filter_map (fun (g : Flow.Workspace.graph) ->
       if g.context = Flow.Workspace.Sop then Some (entry ("of:" ^ g.name) g.name [ "Object"; "Geometry of..." ])
       else None) (fst value.doc.Document.workspace).checked.graphs

(* In a SOP graph: a sop/material of each material graph, after the selection *)
let material_entries value =
  List.filter_map (fun (g : Flow.Workspace.graph) ->
    if g.context = Flow.Workspace.Material then
      Some { Pxui_graph.Node_menu.key = "of-material:" ^ g.name; label = g.name;
             category = [ "Material of..." ]; arity = 1; context = "sop"; output = Flow.Ty.Geometry;
             off = None }
    else None) (fst value.doc.Document.workspace).checked.graphs

(* The graph a menu entry is for, as the entries name it *)
let context_name = function
  | Flow.Workspace.Scene -> "scene" | World -> "world" | Material -> "material" | _ -> "sop"

(* The kinds the node menu offers where the pane shows [graph], at a screen point; the kinds of the
   other graphs follow in the search, in ink-3, saying that they are not placed here.  The title says
   which node the new one goes after. *)
let open_menu value (x, y) =
  match add_target value with
  | Some (_, context) ->
      let module M = Pxui_graph.Node_menu in
      let factories context = M.entries_of_factories ~context:(context_name context) (catalog value context) in
      let not_here entries =
        List.map (fun (e : M.entry) -> { e with off = Some ("not in " ^ context_name context) }) entries in
      let elsewhere =
        (if context = Flow.Workspace.Scene then [] else not_here (scene_entries value))
        @ List.concat_map (fun other -> if other = context then [] else not_here (factories other))
            [ Flow.Workspace.Scene; World; Sop ] in
      let after = match Pxui_graph.Scope.selected value.scope_view with
        | [ path ] when List.length path >= 2 ->
            let last = List.nth path (List.length path - 1) in
            if last = "" || last.[0] = ':' || last.[0] = '@' then None else Some last
        | _ -> None in
      Some (M.create ?after ~x ~y
        (factories context
         @ (if context = Flow.Workspace.Scene then scene_entries value else [])
         @ (if context = Flow.Workspace.Sop then material_entries value else []) @ value_entries
         @ elsewhere))
  | None -> None

(* ---- carry ---- *)

let carry_letters = "asdfghjkl"
let carry_rest = 0.6  (* seconds the pointer rests on a node before the carry enters it *)

(* While a payload is carried the document only navigates: the keys that walk, follow, go back and
   jump work; every edit waits for the put. *)
let carry_allowed : Leader.action -> bool = function
  | Enter | Up | Jump | Guide_toggle | Guide_keys | Frame_tile | Pick_up
  | Scope_command (Pxui_graph.Scope.Walk _ | Frame_all | Frame_selection) -> true
  | _ -> false

let carry_place = function
  | Showing { place; _ } | Held_back { place; _ } | Refused { place; _ } -> place

(* the document the panels read: the scratch copy while a target is hot and its picture is on
   screen, else the one that was there *)
let carry_shown (c : _ carry) = match c.preview with
  | Some (Showing { doc; _ }) -> doc
  | Some (Held_back _ | Refused _) | None -> c.original

(* The put at [place], run on the original: the checker's answer is the preview, the refusal's
   reason and the write.  A put that takes longer than the budget (or onto a cook that does) is
   said and not shown. *)
let carry_try value (c : _ carry) place =
  match Lazy.force value.flow_catalog with
  | None -> Refused { place; reason = "The catalog is unavailable" }
  | Some catalog ->
      let start = Unix.gettimeofday () in
      let result = Carry.put ~factories:value.factories ~catalog c.original c.payload place in
      let spent = Unix.gettimeofday () -. start in
      (match result with
       | Error reason -> Refused { place; reason }
       | Ok (doc, what) ->
           (match value.cook.Cook.seconds with
            | _ when spent >= value.carry_budget ->
                Held_back { place; doc; what;
                            reason = Printf.sprintf "applying takes %d ms" (int_of_float (spent *. 1000.)) }
            | Some cook when cook >= value.carry_budget ->
                Held_back { place; doc; what;
                            reason = Printf.sprintf "a cook takes %d ms" (int_of_float (cook *. 1000.)) }
            | _ -> Showing { place; doc; what }))

(* The key route's letters for the graph the pane shows now (they follow navigation). *)
let carry_targets value (c : _ carry) =
  let graph = graph_name value in
  match c.targets with
  | Some (for_graph, _) when for_graph = graph -> c
  | _ ->
      let found = match Lazy.force value.flow_catalog with
        | None -> []
        | Some catalog -> Carry.targets ~factories:value.factories ~catalog c.original c.payload ~graph in
      { c with targets = Some (graph, List.mapi (fun i (place, label) ->
          String.make 1 carry_letters.[i], place, label) found) }

(* What [y] picks up: the open material or SOP graph; else the graph of the selected geometry
   object; else the selected camera object (by its binding name); else the graph the pane's
   selected node references; else the open scene graph (a viewport shows it). *)
let carry_payload value =
  let ws, _ = value.doc.Document.workspace in
  let context name = Option.map (fun (g : Flow.Workspace.graph) -> g.context)
    (List.find_opt (fun (g : Flow.Workspace.graph) -> g.name = name) ws.checked.graphs) in
  let payload kind name = Ok { Carry.kind; value = "(ref " ^ name ^ ")" } in
  let referenced name = match context name with
    | Some Flow.Workspace.Material -> Some (payload "material" name)
    | Some Sop -> Some (payload "sop" name)
    | _ -> None in
  let opened = Option.bind (graph_name value) (fun name -> referenced name) in
  match opened with
  | Some result -> result
  | None ->
      let object_graph = Option.bind (Selection.selected value.selection) (fun id ->
        if kind value id = Some "geometry" then graph_of_object value id else None) in
      (match Option.bind object_graph referenced with
       | Some result -> result
       | None ->
           (* a camera object: the one selected in the list, else the scene node selected in the pane *)
           let camera_named id =
             if kind value id <> Some "camera" then None else
             match List.assoc_opt id value.doc.Document.homes.objects with
             | Some (Document.Bound_at path) when path <> [] ->
                 Some { Carry.kind = "camera"; value = List.nth path (List.length path - 1) }
             | _ -> None in
           let camera = match Option.bind (Selection.selected value.selection) camera_named with
             | Some _ as found -> found
             | None ->
                 (match Pxui_graph.Scope.selected value.scope_view with
                  | [ path ] ->
                      Option.bind (List.find_map (fun (id, home) ->
                        if home = Document.Bound_at path then Some id else None)
                        value.doc.Document.homes.objects) camera_named
                  | _ -> None) in
           (match camera with
            | Some payload -> Ok payload
            | None ->
                (match Option.bind (follow_target value) referenced with
                 | Some result -> result
                 | None ->
                     (match Option.bind (graph_name value) (fun name ->
                        if context name = Some Flow.Workspace.Scene then Some (payload "scene" name) else None) with
                      | Some result -> result
                      | None -> Error "Nothing to pick up · open a material, SOP or scene graph, or select a geometry or camera object"))))

let carry_cancel value (c : _ carry) ~notice =
  Pxui.Ui.cancel_carry value.ui;
  let doc = c.original in
  let level = Document.resolve_level doc value.level in
  if doc != value.doc then Cook.set_volatile value.cook (Flow_sop.Lower.is_volatile (snd doc.workspace));
  { value with carry = None; doc; level; notice = Some notice;
    workspace = unrestore value.doc doc value.workspace }

let carry_commit value (c : _ carry) doc what =
  Pxui.Ui.cancel_carry value.ui;
  let value = install { value with carry = None } doc ~label:"Put" ~merge:Editor_core.History.Step in
  { value with notice = Some (Info, Printf.sprintf "Put %s · wrote %s · one undo entry" c.payload.value what) }

(* The carry's turn of a frame, before the panes build: the keys of the route and the ends of the
   gesture, then the preview (the scratch document the panels read), or the put or the restore.
   Returns the frame without the keys the carry took, and whether the document shown changed. *)
let carry_step value ~text_focus (frame : Frame.t) =
  match value.carry with
  | None ->
      (match Pxui.Ui.carrying value.ui with
       | Some payload ->
           { value with carry = Some { payload; via = `Pointer;
               original = Editor_core.History.present value.history; settled = value.cook.Cook.pieces;
               report = None; targets = None;
               chosen = None; anchor = None; preview = None; resting = None; hint = None } }, frame, false
       | None -> value, frame, false)
  | Some c ->
      let pressed = List.filter_map (function Event.KeyPressed k -> Some k | _ -> None) frame.events in
      let idle = value.leader = Leader.Idle in
      let escape = idle && List.mem Input.Escape pressed
      and lost = List.exists (function Event.WindowFocusLost -> true | _ -> false) frame.events in
      let typing = (not text_focus) && idle && value.prompt = None && value.menu = None in
      let c = if c.via = `Keys then carry_targets value c else c in
      let letters = match c.targets with
        | Some (_, targets) when c.via = `Keys && typing -> targets | _ -> [] in
      let letter = List.fold_left (fun found key -> match key with
        | Input.KeyChar ch -> (match List.find_opt (fun (l, _, _) -> l = String.make 1 ch) letters with
            | Some _ as hit -> hit | None -> found)
        | _ -> found) None pressed in
      let enter = c.via = `Keys && typing && List.mem Input.Enter pressed in
      let consumed key = (idle && key = Input.Escape)
        || (c.via = `Keys && typing && (key = Input.Enter
            || List.exists (fun (l, _, _) -> Input.KeyChar l.[0] = key) letters)) in
      let taken = { frame with
        events = List.filter (function
          | Event.KeyPressed k | Event.KeyReleased k -> not (consumed k) | _ -> true) frame.events;
        keys = List.filter (fun k -> not (consumed k)) frame.keys } in
      let c = match letter with
        | Some (_, place, _) -> { c with chosen = Some place; anchor = Some frame.mouse; hint = None }
        | None -> c in
      let dropped = match c.report with Some { dropped = true; over } -> Some over | _ -> None
      and hovering = match c.report with Some { dropped = false; over } -> Some over | _ -> None in
      let pointer_wins = match c.anchor with Some at -> frame.mouse <> at | None -> true in
      let desired = match dropped, hovering with
        | Some _, _ -> dropped
        | None, Some _ when pointer_wins -> hovering
        | _ -> c.chosen in
      if escape || lost || (Pxui.Ui.carrying value.ui = None && dropped = None) then
        carry_cancel value c ~notice:(Info, if lost then "Carry dropped · the window lost focus · nothing written"
          else "Carry dropped · nothing written"), taken, true
      else begin
        let preview = if desired = Option.map carry_place c.preview then c.preview
          else Option.map (carry_try value c) desired in
        let c = { c with preview } in
        if dropped <> None || enter then
          (match preview with
           | Some (Showing { doc; what; _ } | Held_back { doc; what; _ }) ->
               carry_commit value c doc what, taken, true
           | Some (Refused { reason; _ }) ->
               carry_cancel value c ~notice:(Refusal, "Refused · " ^ reason ^ " · nothing written"), taken, true
           | None when dropped <> None ->
               carry_cancel value c ~notice:(Info, "Carry dropped · nothing written"), taken, true
           | None -> { value with carry = Some { c with hint = Some "Pick a target letter first, or Esc" } }, taken, false)
        else begin
          (* the pointer resting on a node enters what it references, after a moment *)
          let resting = match hovering with
            | Some (Carry.Node _ as place) ->
                (match c.resting with
                 | Some (q, since) when q = place -> Some (q, since)
                 | _ -> Some (place, frame.time))
            | _ -> None in
          let entered = match resting with
            | Some (Carry.Node path, since) when frame.time -. since >= carry_rest ->
                (* what the original document references, not the preview *)
                follow_target ~path { value with doc = c.original }
            | _ -> None in
          let c = { c with resting = (if entered <> None then None else resting) } in
          let value = { value with carry = Some c } in
          let value = match entered with Some graph -> go value graph | None -> value in
          let shown = carry_shown c in
          if shown == value.doc then value, taken, false
          else begin
            Cook.set_volatile value.cook (Flow_sop.Lower.is_volatile (snd shown.workspace));
            let level = Document.resolve_level shown value.level in
            { value with doc = shown; level; workspace = unrestore value.doc shown value.workspace },
            taken, true
          end
        end
      end

let update_frame ~carry_changed value ~all_ui_visible ~text_focus ~camera_panel ~view_handles
    ~render_status ~error_status ~view_state (frame : Frame.t) =
  let carrying = value.carry <> None in
  let value = { value with workspace = { value.workspace with hidden = shell_hidden value value.workspace } } in
  let value = follow_start value in
  let focus, focus_path = if all_ui_visible then
      match Pxui.Ui.last_press_within value.ui frame
          (List.map fst value.pane_keys) with
      | Some key -> Option.value ~default:(value.focus, value.focus_path)
          (List.assoc_opt key value.pane_keys)
      | None -> value.focus, value.focus_path
    else value.focus, value.focus_path in
  (* a press in another graph panel makes it the pane in use before anything reads the pane *)
  let value = sync_scope (follow_graph value ~focus ~focus_path) in
  (* the other graph panels, laid out from the same document *)
  let other_panes = if not all_ui_visible then [] else
    List.filter_map (fun (key, path) ->
      if value.graph_pane = Some key then None else Some (key, path, sync_scope (as_pane value (key, path))))
      (List.sort_uniq (fun (a, _) (b, _) -> compare a b) (graph_leaves value)) in
  (* the lists, text panes and outlines open, and the ones the focus makes the ones in use *)
  let hosts = if all_ui_visible then panel_hosts value else [] in
  let value = follow_hosts value ~focus_path hosts in
  (* a field of the graph pane owns the keys only while the pane is drawn: one left open when the
     panel turned to its list or text view must not lock the keyboard *)
  let modal = value.prompt <> None || value.menu <> None
    || (all_ui_visible && graph_family value && scope_name value <> None
        && Pxui_graph.Scope.editing value.scope_view)
    || Pxui_shell.Tree.editing value.tree in
  let text_focus = text_focus || modal in
  let keymap = routed { value with focus } in
  let keymap = if all_ui_visible then keymap else List.filter (fun command ->
      match command.Editor_core.Command.action with
      | Leader.List_command _ | Leader.Frame_camera -> false
      | _ -> true) keymap in
  let held_keys = frame.keys in
  let leader, commands, frame = Editor_core.Router.step ~previous_keys:value.held_keys
      keymap ~focus:(Leader.scope focus) ~text_focus ~frame value.leader in
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
  (* Command-Z in a text whose own undo stack is empty (a dragged number applies as it goes)
     reaches the document history, unless a prompt, menu or rename owns the keys *)
  let passed = if text_focus && not modal then
      match Pxui.Ui.passed_undo value.ui with
      | Some `Undo -> [ Leader.Undo ] | Some `Redo -> [ Leader.Redo ] | None -> []
    else [] in
  let actions = passed @ value.queued @ actions in
  let actions = if carrying then List.filter carry_allowed actions else actions in
  let copied = if List.mem Leader.Copy_lisp actions then Some (copy_workspace value) else None in
  (* Command +/-/0: the kit text of the panels (the graph pane zooms, viewports have no text) *)
  List.iter (function
    | Leader.Ui_scale delta ->
        let sizes = [ 8; 9; 10; 11; 12; 13; 14; 16; 18 ] in
        let default = Option.value ~default:5 (List.find_index (( = ) (default_text_size ())) sizes) in
        let here = Option.value ~default (List.find_index (( = ) (Pxui.Ui.font_size value.ui)) sizes) in
        let index = if delta = 0 then default else max 0 (min (List.length sizes - 1) (here + delta)) in
        Pxui.Ui.set_font_size value.ui (List.nth sizes index)
    | _ -> ()) actions;
  let steady = if frame.dt > 0. && frame.dt = value.last_dt then value.steady + 1 else 0 in
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
  let workspace, selection, tree, timeline, timeline_changes = List.fold_left
      (apply_action value)
      (value.workspace, value.selection, value.tree, timeline, timeline_changes) actions in
  let vw = { value with workspace; focus; selection } in
  let graph_shown = all_ui_visible && graph_family vw in
  let listing = listing vw in
  let hosted kind = List.filter (fun (_, _, _, k) -> k = kind) hosts in
  let list_drawn = hosted `List <> [] in
  let ws, _ = value.doc.Document.workspace in
  (* What a text pane shows: a graph panel's own graph and selection, a lisp panel the ones of the
     graph pane in use (the first graph of the workspace when none is open). *)
  (* a panel's pane, laid out: the one in use, or one of the others *)
  let pane_of (key, path, panel, _) =
    let pane = shown_as value (key, path, panel) in
    if pane.graph_pane = value.graph_pane then value
    else match List.find_opt (fun (k, _, _) -> Some k = pane.graph_pane) other_panes with
      | Some (_, _, synced) -> synced | None -> pane in
  let in_use pane = pane.graph_pane = value.graph_pane in
  let text_of state ((_, _, panel, _) as host) =
    let pane = pane_of host in
    let graph = match graph_name pane with
      | None when panel = Lisp -> Option.map (fun (g : Flow.Workspace.graph) -> g.name) (List.nth_opt ws.checked.graphs 0)
      | graph -> graph in
    Option.map (fun graph ->
      let selected = match Pxui_graph.Scope.selected pane.scope_view with
        | [ path ] -> Some path | _ -> None in
      (* while a payload is carried the text is the document it was picked up from: the preview is
         not drawn here, so the byte under the pointer does not move when a put is previewed *)
      let shown_ws = match value.carry with
        | Some c -> fst c.original.Document.workspace
        | None -> ws in
      Text_pane.shown state ~workspace:shown_ws ~source:shown_ws.source ~graph ~selected) graph in
  let text_host = List.find_opt (fun (key, _, _, _) -> Some key = value.text_at) (hosted `Text) in
  let text, text_shown = match Option.bind text_host (text_of value.text) with
    | Some (text, shown) -> text, Some shown
    | None -> value.text, None in
  let other_texts = List.filter_map (fun ((key, path, _, _) as host) ->
    if Some key = value.text_at then None
    else Option.map (fun (state, shown) -> key, path, state, shown) (text_of (local_of value key).code host))
    (hosted `Text) in
  let scope_active = graph_shown && scope_name value <> None in
  let scope_view, scope_command_changes = List.fold_left (fun (view, changes) -> function
    | Leader.Scope_command command when scope_active ->
        let view, emitted = Pxui_graph.Scope.run_command view command in
        view, changes @ emitted
    | Leader.Open_camera -> Pxui_graph.Scope.clear_selection view, changes
    | _ -> view, changes) (value.scope_view, []) actions in
  (* Space a: the node menu of the graph the pane shows *)
  let menu, command_changes =
    if List.mem Leader.Add_node actions && graph_shown then begin
      let gx, gy, gw, gh = match graph_leaf value (geometry value workspace frame) with
        | Some leaf -> leaf.body | None -> 0, 0, 0, 0 in
      let mx, my = frame.mouse in
      let at = if mx >= float gx && my >= float gy && mx < float (gx + gw) && my < float (gy + gh)
        then int_of_float mx, int_of_float my else gx + (gw / 3), gy + (gh / 3) in
      match open_menu value at with
      | Some menu -> Some menu, []
      | None -> value.menu, [ Declined "Open a graph to add a node to it" ]
    end else value.menu, [] in
  let document = document value in
  let displayed = (network value).displayed in
  (* the rows of a level's list, made once per network and kept while a list shows them *)
  let row_sets = ref [] in
  let rows_of pane =
    let network = network pane in
    let key = network.displayed, pane.doc.Document.active_camera in
    let same (source, k, _) = source == network.graph && k = key in
    match List.find_opt same !row_sets with
    | Some (_, _, rows) -> rows
    | None ->
        let entry = match List.find_opt same value.rows with
          | Some entry -> entry | None -> network.graph, key, rows pane network in
        row_sets := entry :: !row_sets;
        let _, _, rows = entry in rows in
  let rows, columns = if listing || list_drawn then rows_of value else [||], [] in
  let selected () = Selection.selected_nodes selection
    |> List.sort (fun a b -> if Some a = Selection.selected selection then -1
      else if Some b = Selection.selected selection then 1 else Int.compare a b) in
  let tree, list_intents = List.fold_left (fun (tree, intents) -> function
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
           | Some id -> Some id | None -> Selection.selected selection)
      | _ -> None) actions in
  let initial_frame_request = if not (List.mem Leader.Frame_camera actions) then None else displayed in
  let bar_action = ref None in
  let view_pick = ref None in  (* a click on the graph header's Graph / List / Text *)
  (* where a carried payload is hovered or released this frame, from panes that are not the graph's *)
  let inspector_drops = ref [] and viewport_drops = ref [] in
  (* what the graph pane marks while a payload is carried: the places that take it (the key
     route's letters) and the one under the pointer *)
  let carry_lit, carry_hot = match value.carry with
    | None -> [], None
    | Some c ->
        let path_of = function
          | Carry.Node p -> Some p
          | Graph g -> Some [ g ]
          | Object id | Surface { object_ = id; _ } ->
              (match List.assoc_opt id value.doc.Document.homes.objects with
               | Some (Document.Bound_at p) -> Some p | _ -> None)
          | Viewport _ | Text _ -> None in
        (match c.targets with
         | Some (_, targets) when c.via = `Keys ->
             List.filter_map (fun (letter, place, _) -> Option.map (fun p -> p, letter) (path_of place)) targets
         | _ -> []),
        Option.bind c.preview (fun preview ->
          Option.map (fun p -> p, (match preview with Showing _ -> true | _ -> false))
            (path_of (carry_place preview))) in
  let build ui =
    (* Chrome first: panel backgrounds, splitters and headers.  Its intents fold into the
       shell now (a fold, a drag) or become one editor-graph edit after the frame. *)
    let header_focus = match focus_path with
      | Some _ as path -> path
      | None -> List.find_map (fun (path, p) -> if p = focus then Some path else None)
                  (Editor_core.Panels.leaves (shell_tree value workspace)) in
    (* the tabs standing at a header's end, outermost first: a graph panel's Graph / List / Text,
       then a text view's Selection / Graph / Document.  [Pxui_shell.Chrome.header_slots] places
       them and cuts the title, so a narrow header drops the text tabs, then the views, and never
       draws one over another *)
    let header_groups (leaf : Pxui_shell.Layout.leaf) =
      let text = match text_host, text_shown with
        | Some (_, path, _, _), Some shown when path = leaf.path -> Some (text, shown)
        | _ -> List.find_map (fun (_, path, state, shown) ->
            if path = leaf.path then Some (state, shown) else None) other_texts in
      (if leaf.panel = Graph then [ Pxui.Ui.text_width ui "GraphListText" +. 24. ] else [])
      @ Option.to_list (Option.map (fun (state, shown) ->
          Text_pane.tabs_width ui ~width:(let _, _, w, _ = leaf.body in w) state shown) text) in
    let header_slots (leaf : Pxui_shell.Layout.leaf) =
      fst (Pxui_shell.Chrome.header_slots leaf (header_groups leaf)) in
    let intents = Pxui_shell.Chrome.update ~state:(panel_state value) ~hidden:workspace.hidden ~title:(panel_title vw)
        ~groups:header_groups
        ~key_of:(fun id -> match List.find_opt (fun (c : Leader.command) -> c.id = id) keymap with
          | Some { trigger = Some trigger; _ } -> Editor_core.Keymap.label trigger | _ -> "")
        ?focus:header_focus (shell_tree value workspace) ui shortcut_frame in
    (* where a header's tools begin: after its title as the chrome laid it out *)
    let tools_from (leaf : Pxui_shell.Layout.leaf) =
      Pxui_shell.Chrome.tools_start ui ~focused:(header_focus = Some leaf.path) ~floating:leaf.floating
        ~collapsed:false (panel_title vw leaf) in
    let leaves = Editor_core.Panels.leaves (shell_tree value workspace) in
    let panel_paths panel = List.filter_map (fun (path, p) -> if p = panel then Some path else None) leaves in
    let toggle panel = List.map (fun path -> Pxui_shell.Chrome.Toggle path) (panel_paths panel) in
    let expand panel = List.filter_map (fun path ->
      if (panel_state value path).collapsed then Some (Pxui_shell.Chrome.Toggle path) else None) (panel_paths panel) in
    let intents = intents @ List.concat_map (function
      | Leader.Toggle_graph -> toggle Graph
      | Toggle_inspector -> toggle Inspector
      | Toggle_timeline -> if panel_paths Timeline = [] then [Pxui_shell.Chrome.Toggle [-1]] else toggle Timeline
      | Open_camera -> expand Inspector
      | Add_node -> expand Graph
      | _ -> []) actions in
    (* Space o ...: the focused panel's split, close and retype, as its header menu *)
    let intents = intents @ (match focused_leaf (geometry value workspace frame) focus focus_path with
      | None -> []
      | Some leaf -> List.filter_map (function
          | Leader.Panel_split axis -> Some (Pxui_shell.Chrome.Split_panel (leaf.path, axis))
          | Panel_close -> Some (Pxui_shell.Chrome.Close_panel leaf.path)
          | Panel_retype (Graph | List | Lisp) when leaf.panel = Graph -> None  (* a view switch, below *)
          | Panel_retype panel -> Some (Pxui_shell.Chrome.Retype_panel (leaf.path, panel))
          | _ -> None) actions) in
    let layout_leaf = focused_leaf (geometry value workspace frame) focus focus_path in
    let workspace, layout_changes = layout_intents vw workspace intents in
    let layout_changes = layout_changes @ layout_actions value workspace ~leaf:layout_leaf actions in
    let vw = { vw with workspace } in
    let g = geometry value workspace frame in
    (* the graph panel's toolbar; a click is one command or edit *)
    let graph_host = graph_leaf vw g in
    (match graph_host with
     | Some leaf when projection vw = Graph_view && has_panel vw Pxui_shell.Layout.Graph ->
         (match Bars.graph_tools ui ~header:leaf.header ~from:(tools_from leaf)
                  ~enabled:(scope_name vw <> None) with
          | Some Add -> bar_action := Some Leader.Add_node
          | Some Repeat -> bar_action := Some (Leader.Scope_command Pxui_graph.Scope.Wrap_repeat)
          | Some Iterate -> bar_action := Some (Leader.Scope_command Pxui_graph.Scope.Wrap_iterate)
          | Some Fn -> bar_action := Some (Leader.Scope_command Pxui_graph.Scope.Make_fn)
          | Some Macro -> bar_action := Some (Leader.Scope_command Pxui_graph.Scope.Make_macro)
          | Some Defn -> bar_action := Some (Leader.Scope_command Pxui_graph.Scope.Make_defn)
          | None -> ())
     | _ -> ());
    (match graph_host with
     | Some leaf when has_panel vw Pxui_shell.Layout.Graph ->
         let _, hy, _, hh = leaf.header in
         let active = match projection vw with Graph_view -> 0 | List_view -> 1 | Text_view -> 2 in
         (* 12 apart, 8 and the 20-point collapse button from the edge (a window: dock and close) *)
         (match Option.bind (List.nth_opt (header_slots leaf) 0) (fun slot -> Option.bind slot (fun right ->
            fst (Pxui_shell.Kit.segments ui ~key:"workspace-view" ~right
                   ~y:(float hy +. float (hh - 20) /. 2.) [ "Graph"; "List"; "Text" ] active))) with
          | Some i -> view_pick := Some (List.nth [ Graph_view; List_view; Text_view ] i)
          | None -> ())
     | _ -> ());
    (match active_view vw g, value.view_tools with
     | Some ({ header = (hx, hy, hw, hh); _ } as leaf), Some (looks, mode) when hh > 0 ->
         let from = float hx +. tools_from leaf in
         let modes = [ "Solid"; "Wire"; "Traced" ] in
         let seg_w = List.fold_left (fun w label -> w +. Pxui.Ui.text_width ui label) 24. modes in
         let look_w = Pxui_shell.Kit.button_width ui ~hint:"C" "Look through" in
         let ty = float hy +. float (hh - 20) /. 2. in
         let frame_w = Pxui_shell.Kit.button_width ui ~hint:"F" "Frame" in
         if from +. seg_w +. 8. +. look_w +. 8. +. frame_w < float (hx + hw - 36) then begin
           Bars.rule ui ~key:"workspace-view-rule" ~header:leaf.header ~from:(from -. float hx);
           (match fst (Pxui_shell.Kit.segments ui ~key:"workspace-render" ~right:(from +. seg_w) ~y:ty modes mode) with
            | Some i when i <> mode -> bar_action := Some (Leader.Render_mode i)
            | _ -> ());
           if Pxui_shell.Kit.button ui ~key:"workspace-look" ~at:(from +. seg_w +. 8., ty) ~w:look_w
                ~active:looks ~hint:"C" "Look through"
           then bar_action := Some Leader.Look_through;
           (* the key's own command (view.frame-camera): the camera onto the displayed node *)
           if Pxui_shell.Kit.button ui ~key:"workspace-frame" ~at:(from +. seg_w +. 8. +. look_w +. 8., ty) ~w:frame_w
                ~hint:"F" "Frame"
           then bar_action := Some Leader.Frame_camera
         end
     | _ -> ());
    let root order (leaf : Pxui_shell.Layout.leaf) =
      let box = Pxui_shell.Chrome.pane_root ui frame ~bounds:leaf.body
        ("workspace-pane-" ^ Leader.pane_name leaf.panel ^ Pxui_shell.Chrome.key leaf.path) in
      if leaf.floating then Pxui.Ui.to_front ui ~order box;
      box in
    let roots = List.mapi (fun order leaf -> leaf, root order leaf) g.leaves in
    if carrying then List.iter (fun ((leaf : Pxui_shell.Layout.leaf), box) -> match leaf.panel with
      | View key ->
          Option.iter (fun d -> viewport_drops := (Carry.Viewport key, (match d with
            | Pxui.Ui.Dropped _ -> true | Hover _ -> false)) :: !viewport_drops)
            (Pxui.Ui.drop_target ui box)
      | _ -> ()) roots;
    let timeline_root = if Pxui_shell.Layout.find g Timeline <> None then None
      else Some (Pxui_shell.Layout.Timeline, Pxui_shell.Chrome.pane_root ui frame ~bounds:g.timeline_at
        "workspace-pane-Timeline") in
    (* every leaf draws in its own root: its PXUI keys are seeded by it *)
    let root_at path = List.find_opt (fun ((l : Pxui_shell.Layout.leaf), _) ->
      l.path = path && (let _, _, _, h = l.body in h > 0)) roots in
    let of_kind panel = List.filter (fun ((l : Pxui_shell.Layout.leaf), _) ->
      l.panel = panel && visible workspace panel && (let _, _, _, h = l.body in h > 0)) roots in
    let none_root () = Pxui_shell.Chrome.pane_root ui frame ~bounds:(0, 0, 0, 0) "workspace-pane-none" in
    let graph_root = match Option.bind graph_host (fun (l : Pxui_shell.Layout.leaf) -> root_at l.path) with
      | Some (_, box) -> box | None -> none_root () in
    let active = active_view vw g in
    (* What is painted over a view stays in its pane: the box the marks are drawn in fills a
       clipping one ([Ui.clip] binds a box's children, not its own paint), so a bracket, a label
       or a frame that runs past the pane's edge is cut there and never lies on its neighbour. *)
    let view_layer ui (bx, by, bw, bh) key =
      let pane = Pxui.Ui.box ui ~flags:Pxui.Ui.clip ~w:(Pxui.Ui.Px (float bw)) ~h:(Pxui.Ui.Px (float bh))
          ~at:(float bx, float by) key in
      Pxui.Ui.within ui pane (fun () -> Pxui.Ui.box ui ~w:Pxui.Ui.Grow ~h:Pxui.Ui.Grow "marks") in
    (* the iteration the selected node shows, over the viewport's lower left corner *)
    (match probe_caption vw, active with
     | Some text, Some (leaf : Pxui_shell.Layout.leaf) ->
         (* a label on the ground, like every readout over the view *)
         Pxui.Ui.draw ui (view_layer ui leaf.body "viewport-caption") (fun paint (x, y, _, h) ->
           let px = x +. 12. and py = y +. h -. 24. in
           let theme = Pxui.Ui.theme ui in
           Pxui.Ui.Paint.fill paint ~x:(px -. 4.) ~y:py ~w:(Pxui.Ui.Paint.cap_width paint text +. 8.) ~h:16. theme.panel;
           Pxui.Ui.Paint.cap paint ~at:(px, py +. 2.) text)
     | _ -> ());
    (* over each view, in the kit's marks (viewport.html): the render frame and its label, the
       traced readout at the upper left, the render camera at the upper right, the selected
       object's brackets and name, and the scene's size and the frame rate at the lower right;
       every label is a row high and sits on a patch of the ground *)
    let module P = Pxui.Ui.Paint in
    let theme = Pxui.Ui.theme ui in
    let rh = float (Pxui.Ui.row_height ui) in
    let cap_y y = Pxui_shell.Kit.cap_y ui y rh in
    (* a label in the row at [y]; [pl] and [pr] points of ground beside it; its width *)
    let label paint ~x ~y ?(pl = 0.) ?(pr = 0.) ?color text =
      let w = P.cap_width paint text in
      P.fill paint ~x:(x -. pl) ~y ~w:(w +. pl +. pr) ~h:rh theme.panel;
      P.cap paint ~at:(x, cap_y y) ?color text; w in
    (* a viewport window labels its frame at the top left: the shading and the camera ("Wire · top") *)
    List.iter (fun ((leaf : Pxui_shell.Layout.leaf), _) -> match leaf.panel, value.view_tools with
      | View key, Some (_, mode) when leaf.floating && (let _, _, w, h = leaf.body in w > 120 && h > 60) ->
          let bx, by, _, _ = leaf.body in
          let camera = Option.bind value.doc.Document.active_camera (fun id ->
            Option.map Node.label (Edit_graph.find (scene value) ~node_id:id)) in
          let text = String.concat " \xc2\xb7 " ([ List.nth [ "Solid"; "Wire"; "Traced" ] (max 0 (min 2 mode)) ]
            @ Option.to_list camera) in
          let w = Pxui_shell.Kit.cap_width ui text +. 8. in
          let box = Pxui.Ui.box ui ~w:(Pxui.Ui.Px w) ~h:(Pxui.Ui.Px 16.)
              ~at:(float bx +. 8., float by +. 4.) ("viewport-window-label-" ^ key) in
          Pxui.Ui.to_front ui ~order:max_int box;
          Pxui.Ui.draw ui box (fun paint (x, y, _, h) ->
            Pxui.Ui.Paint.cap paint ~at:(x +. 4., Pxui_shell.Kit.cap_y ui y h) text)
      | _ -> ()) roots;
    List.iter (fun ((leaf : Pxui_shell.Layout.leaf), _) -> match leaf.panel with
      | View key when (let _, _, w, h = leaf.body in w > 320 && h > 160) ->
          let _, _, bw, _ = leaf.body in
          let overlay = view_layer ui leaf.body ("viewport-marks-" ^ key) in
          let gate = List.assoc_opt key value.gates in
          let box = match value.selected_box with Some (k, rect, name) when k = key -> Some (rect, name) | _ -> None in
          let root : Objects.Root.parameters = Option.fold ~none:value.doc.Document.root
              ~some:(fun (r : Document.view_root) -> r.params) (List.assoc_opt key value.doc.Document.view_roots) in
          let camera = Option.bind value.doc.Document.active_camera (fun id -> Edit_graph.find (scene value) ~node_id:id) in
          (* the triangles the scene draws: a polygon of n corners fans into n - 2 (exact for polygons, a
             count of corners and faces, not a walk of every face, for a frame's cost) *)
          let tris = List.fold_left (fun n (piece : _ Cook.piece) ->
            let g = piece.output.Procedural.Session.geometry in
            n + max 0 (Rdk.Geometry.vertex_count g - (2 * Rdk.Geometry.primitive_count g))) 0 (pieces value) in
          let objects = List.length (pieces value) in
          let points = Option.map (fun (piece : _ Cook.piece) ->
            Rdk.Geometry.point_count piece.output.Procedural.Session.geometry) (piece value) in
          (* the traced readout: its samples are the caption's "n/cap spp" *)
          let traced = List.assoc_opt key value.traces in
          (* a body about as wide as the workspace sheet's follows that sheet: the narrow traced
             block, no camera readout, no object count; a wide one follows viewport.html *)
          let narrow = bw < 1000 in
          Pxui.Ui.draw ui overlay (fun paint (x, y, w, h) ->
            Option.iter (fun (gx, gy, gw, gh) ->
              let gx = float gx and gy = float gy and gw = float gw and gh = float gh in
              P.stroke paint ~x:(gx +. 0.5) ~y:(gy +. 0.5) ~w:(gw -. 1.) ~h:(gh -. 1.) (Pxui.Theme.edge theme);
              (* the corner marks lie on the frame's own edge: 16 points, 1 wide, in ink *)
              P.brackets paint ~x:gx ~y:gy ~w:gw ~h:gh ~offset:0. ~length:16. ~width:1. theme.foreground;
              (* the label stands over the frame's left end with no ground of its own; the traced
                 readout, drawn after it, covers its head where the sheet's does *)
              P.cap paint ~at:(gx, cap_y (if gy -. y >= 20. then gy -. 20. else gy +. 4.))
                (Printf.sprintf "Render frame \xc2\xb7 %d \xc3\x97 %d" root.width root.height)) gate;
            (* a traced viewport's readout: the path tracer and its backend as labels, the samples as
               a 20-point count over a 4-point bar, the film as a label; 4 apart, on the ground *)
            Option.iter (fun (t : trace) ->
              if w > 200. && h > 120. then begin
                (* the readout's ground stands 8 clear of its text and bar on both sides *)
                let fx = x +. (if narrow then 8. else 12.) and oy = y +. (if narrow then 8. else 12.) in
                let ox = fx +. 8. in
                let title = Pxui.Ui.font_size ui * Pxui.Theme.title_size / Pxui.Theme.font_size in
                let bar_w = if narrow then 112. else Float.min 224. (w -. 24.) in
                P.fill paint ~x:fx ~y:oy ~w:(bar_w +. 16.) ~h:((3. *. rh) +. 24.) theme.panel;
                let tw = label paint ~x:ox ~y:oy ~color:theme.foreground "Path traced" in
                if not narrow then
                  ignore (P.cap paint ~at:(ox +. tw +. 6., cap_y oy) ~color:(Pxui.Theme.ink_2 theme) "Metal RT");
                let ty = Pxui.Ui.text_top ui ~size:title in
                let row2 = oy +. rh +. 4. in
                let count = string_of_int (min t.samples t.cap) in
                P.text paint ~size:title ~at:(ox, ty row2 rh -. 1.) ~color:theme.foreground count;
                P.text paint ~size:title
                  ~at:(ox +. P.text_width paint ~size:title (count ^ " "), ty row2 rh -. 1.)
                  ~color:(Pxui.Theme.ink_2 theme)
                  (if narrow then Printf.sprintf "/ %d" t.cap else Printf.sprintf "/ %d spp" t.cap);
                (* the bar: a line-3 box 4 high, filled inside it with the share of the samples *)
                let by = row2 +. rh +. 4. in
                P.stroke paint ~x:(ox +. 0.5) ~y:(by +. 0.5) ~w:(bar_w -. 1.) ~h:3. (Pxui.Theme.border theme);
                P.fill paint ~x:(ox +. 1.) ~y:(by +. 1.) ~w:((bar_w -. 2.) *. Float.min 1. (float t.samples /. float (max 1 t.cap)))
                  ~h:2. theme.foreground;
                (* under it: the seconds the accumulation took and, on a wide body, the bounces and
                   the film in pixels *)
                let fw, fh = t.film in
                ignore (P.cap paint ~at:(ox, cap_y (by +. 8.))
                  (if narrow then Printf.sprintf "spp \xc2\xb7 %.1f s" t.seconds
                   else Printf.sprintf "%.1f s \xc2\xb7 %d bounce%s \xc2\xb7 %d \xc3\x97 %d" t.seconds t.bounces
                     (if t.bounces = 1 then "" else "s") fw fh))
              end) traced;
            Option.iter (fun ((sx, sy, sw, sh), name) ->
              let sx = float sx and sy = float sy and sw = float sw and sh = float sh in
              if sw > 8. && sh > 8. then begin
                P.brackets paint ~x:sx ~y:sy ~w:sw ~h:sh theme.accent;
                (* the name in the accent, in the row that ends where the brackets begin, then how
                   many points the object cooked to, on the ground *)
                let ny = sy -. 4. -. rh in
                P.cap paint ~at:(sx -. 4., cap_y ny) ~color:theme.accent name;
                Option.iter (fun n ->
                  let digits = string_of_int n in
                  let grouped = String.concat " " (List.rev (let rec chop s = if String.length s <= 3 then [ s ]
                    else String.sub s (String.length s - 3) 3 :: chop (String.sub s 0 (String.length s - 3)) in chop digits)) in
                  ignore (label paint ~x:(sx -. 4. +. P.cap_width paint name +. 8.) ~y:ny ~pl:4. ~pr:4.
                    ~color:(Pxui.Theme.ink_2 theme) (grouped ^ " pts"))) points
              end) box;
            (* the render camera: its name, its lens and focus as a two-column grid whose labels
               and values both end at their column's right edge, 10 apart *)
            if not narrow then Option.iter (fun node ->
              let field name = List.find_map (fun (f : Parameter.field_view) ->
                match f.name = name, f.current with
                | true, Parameter.Float_value v -> Some v | _ -> None) (Node.parameter_fields node) in
              let rows = [ "Camera", Node.label node ]
                @ (match field "fov" with
                   | Some fov when fov > 0. && fov < 180. ->
                       (* the focal length that gives this vertical angle on a 24 mm gate *)
                       let mm = 12. /. Float.tan (fov *. Float.pi /. 360.) in
                       [ "Lens", Printf.sprintf "%.0f mm" mm
                         ^ (match field "aperture" with Some a when a > 0. -> Printf.sprintf " \xc2\xb7 r %g" a | _ -> "") ]
                   | _ -> [])
                @ (match field "focus_distance" with Some d when d > 0. -> [ "Focus", Printf.sprintf "%.2f" d ] | _ -> []) in
              let value_w = List.fold_left (fun m (_, v) -> Float.max m (P.text_width paint v)) 0. rows in
              let label_w = List.fold_left (fun m (l, _) -> Float.max m (P.cap_width paint l)) 0. rows in
              let right = x +. w -. 12. in
              P.fill paint ~x:(right -. value_w -. 10. -. label_w -. 8.) ~y:(y +. 12.)
                ~w:(value_w +. 10. +. label_w +. 8.) ~h:((rh *. float (List.length rows)) +. 4.) theme.panel;
              List.iteri (fun i (name, text) ->
                let ry = y +. 12. +. (rh *. float i) in
                P.cap paint ~at:(right -. value_w -. 10. -. P.cap_width paint name, cap_y ry) name;
                P.text paint ~at:(right -. P.text_width paint text, Pxui_shell.Kit.text_y ui ry rh)
                  ~color:theme.foreground text) rows) camera;
            (* the scene's size and the frame rate: labels 12 apart, the rate in ink, in the row
               that ends 12 (6 on a narrow body) above the pane's foot *)
            let edge = if narrow then 8. else 12. in
            let row_y = y +. h -. (if narrow then 6. else 12.) -. rh in
            let tris_text = Printf.sprintf "%s tris" (group_thousands tris) in
            let items =
              (tris_text, None)
              :: (if narrow then [] else
                  [ Printf.sprintf "%d object%s" objects (if objects = 1 then "" else "s"), None ])
              @ (match value.status_fps with Some fps -> [ Printf.sprintf "%d fps" fps, Some theme.foreground ] | None -> []) in
            let total = List.fold_left (fun sum (text, _) -> sum +. P.cap_width paint text) (12. *. float (List.length items - 1)) items in
            (* the wide sheet's readout stands on a patch of the ground; the narrow one on the view *)
            if not narrow then P.fill paint ~x:(x +. w -. edge -. total -. 8.) ~y:row_y ~w:(total +. 8.) ~h:rh theme.panel;
            ignore (List.fold_left (fun at (text, color) ->
              P.cap paint ~at:(at, cap_y row_y) ?color text;
              at +. P.cap_width paint text +. 12.) (x +. w -. edge -. total) items))
      | _ -> ()) roots;
    let view_root = match active with
      | Some leaf -> snd (List.find (fun ((l : Pxui_shell.Layout.leaf), _) -> l == leaf) roots)
      | None -> none_root () in
    let graph_body = match graph_host with Some leaf -> leaf.body | None -> 0, 0, 0, 0 in
    let gx, gy, gw, gh = graph_body in
    let scope_view, scope_frame_changes =
      if not scope_active then scope_view, []
      else Pxui.Ui.within ui graph_root (fun () ->
        scope_view
        |> Pxui_graph.Scope.with_guide guide
        |> Pxui_graph.Scope.with_failed (failed_nodes value)
        |> Pxui_graph.Scope.with_theme (let theme = Pxui.Ui.theme ui in
             match graph_host with Some { floating = true; _ } -> sheet_theme theme | _ -> theme)
        |> Pxui_graph.Scope.with_bounds ~x:gx ~y:gy ~width:(max 1 gw) ~height:(max 1 gh)
        |> Pxui_graph.Scope.with_visible true
        |> Pxui_graph.Scope.with_carry ~lit:carry_lit ~hot:carry_hot
        |> fun view -> Pxui_graph.Scope.update view ui shortcut_frame) in
    (* a right-click on the pane's empty canvas opens the add menu there *)
    let menu = match menu, List.find_map (function
        | Pxui_graph.Scope.Menu_requested (x, y) -> Some (int_of_float x, int_of_float y)
        | _ -> None) scope_frame_changes with
      | None, Some at -> open_menu value at
      | menu, _ -> menu in
    let menu, menu_pick = match menu with
      | Some menu -> Pxui.Ui.within ui graph_root (fun () ->
          Pxui_graph.Node_menu.update menu ui ~bounds:(0, 0, frame.width, (let _, sy, _, _ = (geometry value workspace frame).status_at in sy)))
      | None -> None, None in
    (* every list shows the level and selection of its graph panel, with its own folds, filter and
       scroll; the one in use takes the keys.  A list of another pane only shows: a press makes its
       pane the one in use before the frame builds *)
    let tree, list_intents, locals = List.fold_left (fun (tree, intents, locals) ((key, path, _, _) as host) ->
      match root_at path with
      | None -> tree, intents, locals
      | Some ((leaf : Pxui_shell.Layout.leaf), root) ->
          let pane = pane_of host in
          let mine = in_use pane in
          let rows, columns = if mine then rows, columns else rows_of pane in
          let selected = if mine then selected () else Selection.selected_nodes pane.selection in
          let draw state = on_sheet ui leaf.floating (fun () -> Pxui.Ui.within ui root (fun () ->
            Pxui_shell.Tree.update state ui shortcut_frame ~bounds:leaf.body
              ~title:(level_name pane) ~columns rows ~selected)) in
          if Some key = value.list_at then
            let tree, emitted = draw tree in tree, (if mine then intents @ emitted else intents), locals
          else
            let state, emitted = draw (local_of value key).rows in
            tree, (if mine then intents @ emitted else intents), put_local key (fun l -> { l with rows = state }) locals)
      (tree, list_intents, value.locals) (hosted `List) in
    let names = lazy (completion_names value) in
    let view_text path state shown = match root_at path with
      | Some ((leaf : Pxui_shell.Layout.leaf), root) ->
          Pxui.Ui.within ui root (fun () ->
            Text_pane.view ui ~bounds:leaf.body
              (* a graph panel in text view keeps its Graph / List / Text at the header's end *)
              ~tabs_right:(Option.join (List.nth_opt (List.rev (header_slots leaf)) 0))
              ~vocab:(Lazy.force value.lisp_vocab) ~names:(Lazy.force names) state shown)
      | None -> [] in
    let text_intents = match text_shown, text_host with
      | Some shown, Some (_, path, _, _) -> view_text path text shown
      | _ -> [] in
    (* every other text pane, with its own tab and drafts *)
    let locals, other_texts = List.fold_left (fun (locals, texts) (key, path, state, shown) ->
      put_local key (fun l -> { l with code = state }) locals, (key, shown, view_text path state shown) :: texts)
      (locals, []) other_texts in
    let outline, outline_intents, locals = List.fold_left (fun (outline, intents, locals) (key, path, _, _) ->
      match root_at path with
      | None -> outline, intents, locals
      | Some ((leaf : Pxui_shell.Layout.leaf), root) ->
          let draw state = on_sheet ui leaf.floating (fun () -> Pxui.Ui.within ui root (fun () ->
            Navigator.view state ui ~bounds:leaf.body (navigator_params value))) in
          if Some key = value.outline_at then let outline, emitted = draw outline in outline, intents @ emitted, locals
          else
            let state, emitted = draw (local_of value key).nav in
            outline, intents @ emitted, put_local key (fun l -> { l with nav = state }) locals)
      (value.outline, [], locals) (hosted `Outline) in
    (* every other graph panel draws its own canvas; a press gives a panel the focus before the
       frame builds, so the pane a gesture starts in is the one in use *)
    let graph_panes = List.filter_map (fun (key, path, (pane : _ t)) ->
      match List.find_opt (fun ((l : Pxui_shell.Layout.leaf), _) -> l.path = path) roots with
      | Some (leaf, hosted) when (let _, _, _, h = leaf.body in h > 0) ->
          let x, y, width, height = leaf.body in
          let view = if stored_projection pane = Graph_view && graph_name pane <> None then
              Pxui.Ui.within ui hosted (fun () ->
                pane.scope_view
                |> Pxui_graph.Scope.with_guide false
                |> Pxui_graph.Scope.with_theme (let theme = Pxui.Ui.theme ui in
                     if leaf.floating then sheet_theme theme else theme)
                |> Pxui_graph.Scope.with_bounds ~x ~y ~width:(max 1 width) ~height:(max 1 height)
                |> Pxui_graph.Scope.with_visible true
                |> fun view -> fst (Pxui_graph.Scope.update view ui shortcut_frame))
            else pane.scope_view in  (* its list or text view is drawn with the lists and text panes *)
          Some (key, { (stash pane) with view })
      | _ -> Some (key, stash pane)) other_panes in
    let scope_changes = scope_command_changes @ scope_frame_changes in
    let changes = command_changes
      @ List.concat_map (function
        | Pxui_graph.Scope.Syntax_edit op -> [ Syntax_edit op ]
        | Notice message -> [ Declined message ]  (* the pane's notices are all refusals *)
        | Defn_requested paths -> [ defn_change vw paths ]
        | Copy_requested paths -> [ copy_bindings value paths ]
        | Paste_requested -> paste_bindings value
        | _ -> []) scope_changes
      @ (match menu_pick with Some key -> scope_add value key | None -> [])
      @ List.filter_map (function
        | Navigator.Set_default { graph; input; value; integer } ->
            let text = if integer then string_of_int (int_of_float (Float.round value))
              else Flow.Lisp.float value in
            Some (Syntax_edit (Flow_sop.Flow_edit.Set_input_default { form = graph; input;
              value = Flow.Syntax.make (Flow.Syntax.Num text) }))
        | Rename { graph; to_ } -> Some (Syntax_edit (Flow_sop.Flow_edit.Rename_graph { name = graph; to_ }))
        | Remove graph -> Some (Syntax_edit (Flow_sop.Flow_edit.Remove_graph { name = graph }))
        | Flag { node; name; value } ->
            Some (Syntax_edit (Flow_sop.Flow_edit.Set_arg { node; key = Flow_sop.Flow_edit.Kw name; sub = [];
              value = Flow.Syntax.make (Flow.Syntax.Sym (if value then "true" else "false")) }))
        | Open _ | Macro _ | Layout _ | Add -> None) outline_intents in
    (* a layout row and the add button are commands: they run like a toolbar click *)
    List.iter (function
      | Navigator.Layout index -> bar_action := Some (Leader.Layout_switch index)
      | Add -> bar_action := Some Leader.Add_node
      | _ -> ()) outline_intents;
    (* Selection is view state; inspection intents retain the selected stable
       id. Topology and parameter application wait until Ui.frame finishes. *)
    let selection = List.fold_left (fun selection -> function
      | Pxui_shell.Tree.Select [] -> Selection.clear selection
      | Select ids -> Selection.select_nodes ids selection
      | _ -> selection) selection list_intents in
    let inspector_visible = has_panel vw Pxui_shell.Layout.Inspector in
    let selected_ids = Selection.selected_nodes selection in
    let selected_id = match selected_ids with
      | [_] -> Selection.selected selection | _ -> None in
    let selected = Option.bind selected_id
        (fun node_id -> Edit_graph.find document ~node_id) in
    let unchanged = value.doc.settings in
    let lowered_level = match value.level with
      | Document.Inside id -> kind value id = Some "geometry" | Scene -> false in
    let workspace_requests = ref [] and workspace_moves = ref [] in
    (* the split a card of the editor graph is, sized another way from what it shows now *)
    let resized node how = match node, value.doc.Document.shell with
      | [ graph; name ], Some shell when not workspace.restored
          && Option.map (fun (g : Flow.Workspace.graph) -> g.name)
               (Workspace_doc.editor_graph (fst value.doc.Document.workspace)) = Some graph ->
          Option.bind (List.find_map (fun (path, origin) ->
            if origin = Document.Bound name then Some path else None) shell.origins) (fun path ->
            Option.map (fun splitter -> Pxui_shell.Layout.resized splitter how)
              (List.find_opt (fun (s : Pxui_shell.Layout.splitter) -> s.node = Some path) g.splitters))
      | _ -> None in
    (* every inspector shows the same selection in its own root (its scroll and open sections are
       its own); the edits of all are this frame's, the host's panel is the focused one's *)
    let inspect (value, scope_view, selection, scope_active) inspector_root bounds =
      let document = (network value).graph.geometry in
      let selected_ids = Selection.selected_nodes selection in
      let lowered_level = match value.level with
        | Document.Inside id -> kind value id = Some "geometry" | Scene -> false in
      (* a row of a geometry object's list selects its node in the pane: the inspector follows it *)
      let scope_selected = if scope_active || (lowered_level && value.scope_key <> None)
        then Pxui_graph.Scope.selected scope_view else [] in
      let open_network = network value in
      let window = List.exists (fun (l : Pxui_shell.Layout.leaf) -> l.floating && l.panel = Inspector && l.body = bounds) g.leaves in
      (* a window keeps its 1-point border on the left, right and bottom: its panel lies inside *)
      let bounds = if window then (let x, y, w, h = bounds in x, y, max 1 w, max 1 (h - 1)) else bounds in
      let inspector_panel ui bounds build = inspector_panel ~window ui bounds build in
      on_sheet ui window
      @@ fun () -> Pxui.Ui.within ui inspector_root (fun () -> match selected_ids with
      | _ when not inspector_visible ->
          None, [], [], value.live_cook
      | _ when scope_selected <> [] ->
          let () = match scope_selected with
            | [ path ] ->
                let requests, moves = inspector_panel ui bounds (fun () ->
                  workspace_inspector ~window value ui ~width:(float (let _, _, w, _ = bounds in max 1 w)) path ~resized
                    ~follows:(fun path -> follow_target ~path value)
                    ~on_choice:(fun name box -> if name = "@ref:material" then
                      Option.iter (fun d -> inspector_drops := (Carry.Node path, (match d with
                        | Pxui.Ui.Dropped _ -> true | Hover _ -> false)) :: !inspector_drops)
                        (Pxui.Ui.drop_target ui box))) in
                workspace_requests := requests; workspace_moves := !workspace_moves @ moves
            | paths -> inspector_panel ui bounds (fun () ->
                ignore (Pxui.Ui.inspector_header ui ~key:"multi-header"
                  ~title:(Printf.sprintf "%d nodes" (List.length paths)) ~detail:"Selected" ())) in
          None, !workspace_requests, [], value.live_cook
      | [] ->
          (* Sketch settings above the environment's camera/render panel. *)
          let changes, live, panel = inspector_panel ui bounds (fun () ->
            let node_count = List.length (Edit_graph.inspect document) in
            let display = Option.fold ~none:"none" ~some:(fun id ->
              Option.fold ~none:("#" ^ string_of_int id) ~some:Node.label
                (Edit_graph.find document ~node_id:id)) open_network.displayed in
            let title, detail = match value.scope_key with
              | Some k when scope_active && Some k.graph = graph_name value ->
                  let rec count (s : Flow_sop.Projection.scope) = List.fold_left
                    (fun n (x : Flow_sop.Projection.node) ->
                      n + 1 + Option.fold ~none:0 ~some:(fun (z : Flow_sop.Projection.zone) -> count z.scope) x.zone)
                    0 s.nodes in
                  let zones = List.length (Flow_sop.Projection.zones k.scope) in
                  k.graph, Printf.sprintf "%d node%s · %d loop%s · select a node to edit it" (count k.scope)
                    (if count k.scope = 1 then "" else "s") zones (if zones = 1 then "" else "s")
              | _ -> level_name value, Printf.sprintf "%d node%s · display %s" node_count (if node_count = 1 then "" else "s") display in
            ignore (Pxui.Ui.inspector_header ui ~key:"network-header" ~title ~detail ());
            Pxui.Ui.inspector_body ui (fun () ->
            (* the row sits under a section named for the graph, as every row of the sheet does *)
            let live = Option.value ~default:value.live_cook (Pxui.Ui.inspector_section ui
                ~key:"live-cook-section" ~expanded:true title (fun () ->
                  Pxui.Ui.inspector_toggle ui ~key:"live-cook" ~label:"Live update" value.live_cook)) in
            let changes = match Settings.fields unchanged |> List.filter (fun (field : Parameter.field_view) ->
                field.name <> "renderer") with
              | [] -> []
              | fields ->
                  Pxui.Ui.scope ui "sketch-settings" (fun () ->
                    let _, _, width, _ = bounds in
                    Option.value ~default:[] (Pxui.Ui.inspector_section ui
                      ~key:"sketch-settings-section" ~expanded:true "Settings"
                      (fun () -> Pxui_shell.Inspector.fields ui
                        ~width:(float width) fields))) in
            changes, live, camera_panel ())) in
          Some panel, [], changes, live
      | _ :: _ :: _ ->
          let () = inspector_panel ui bounds (fun () ->
            ignore (Pxui.Ui.inspector_header ui ~key:"multi-header"
              ~title:(Printf.sprintf "%d nodes" (List.length selected_ids))
              ~detail:"Selected" ())) in
          None, [], [], value.live_cook
      | [node_id] ->
          (* the nodes of a geometry object are the lowering of its graph: the graph pane's node
             is the one to edit (its arguments are the text) *)
          let derived = match value.level with
            | Document.Inside id -> kind value id = Some "geometry" | Scene -> false in
          let fields, label, kind = match Edit_graph.find document ~node_id with
            | Some node -> Node.parameter_fields node, Node.label node, Node.operation node
            | None -> [], "#" ^ string_of_int node_id, "unknown" in
          let preview = value.level = Document.Scene && Option.fold ~none:false
            ~some:(fun shell -> List.exists (fun (_, ids) -> List.mem node_id ids) shell.Document.views)
            value.doc.shell in
          let changes = inspector_panel ui bounds (fun () ->
            Pxui.Ui.scope ui (Printf.sprintf "node.%d" node_id) (fun () ->
              let _, _, inspector_width, _ = bounds in
              let inspector_width = float (max 1 inspector_width) in
              let input_count = Array.length (Option.value ~default:[||] (Edit_graph.inputs document ~node_id)) in
              (* the head: the kind as the sheet writes it (scene/camera), VIEW while displayed,
                 the node's number; the name edited in place; what is true of the node *)
              let facts = List.filter_map Fun.id [
                if Edit_graph.is_bypassed document ~node_id then Some "muted" else None;
                if value.doc.Document.active_camera = Some node_id then Some "active camera" else None;
                if input_count > 0 then Some (Printf.sprintf "%d input%s" input_count (if input_count = 1 then "" else "s"))
                else None;
                if preview then Some "preview instance" else None ] in
              let head = Pxui.Ui.inspector_header ui
                  ~key:"flow-inspector-header"
                  ~kind:(Printf.sprintf "%s/%s" (Flow.Context.name open_network.context) kind)
                  ?badge:(if open_network.displayed = Some node_id then Some "view" else None)
                  ~index:(Printf.sprintf "NO. %04d" node_id)
                  ?rename:(if derived || preview then None else Some (fun text -> String.trim text <> ""))
                  ~title:label
                  ~detail:(match facts with
                    | [] -> Printf.sprintf "%d parameter%s" (List.length fields) (if List.length fields = 1 then "" else "s")
                    | facts -> String.concat " · " facts) () in
              let renamed = head.renamed in
              let rename = if renamed = label || derived || preview then [] else
                [Rename {node = node_id; label = renamed}] in
              rename @ Pxui.Ui.inspector_body ui (fun () ->
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
                      ~label:name ("← " ^ source)) inputs));
              if derived then Pxui.Ui.inspector_message ui ~key:"flow-derived"
                "Made from the graph's text. Select the node in the graph pane to edit its arguments.";
              if preview then Pxui.Ui.inspector_message ui ~key:"flow-preview"
                "Preview instance. Edit its viewport scene reference or source graph.";
              let edits = match object_rows ~locked:(derived || preview) fields with
                | Error diagnostic ->
                    Pxui.Ui.inspector_message ui ~key:"flow-diagnostic"
                      (Flow.Diagnostic.to_string diagnostic); []
                | Ok [] -> []
                | Ok rows ->
                    let expanded = fields |> List.filter_map (fun field ->
                      match field.Parameter.folder with [] -> None
                      | first :: _ -> Some first) |> List.sort_uniq String.compare in
                    Pxui_shell.Inspector.flow_fields ui ~expanded ~actions:false
                      ~kind_label:(kind_label kind) ~width:inspector_width rows in
              List.filter_map (function
                | Pxui_shell.Inspector.Edited (path, value) ->
                    Some (Set_parameter {node = node_id; path; value})
                | Pxui_shell.Inspector.Expression (path, text) ->
                    (* a row is a field of the node; its argument is the parameter holding it (a
                       vector's field is one component of it) *)
                    let parameters = Result.value ~default:[] (Flow_sop.Port.parameters (Editor_document.Contexts.group_triples fields)) in
                    let key_sub = List.find_map (fun (p : Flow_sop.Port.parameter) ->
                      match List.find_index (fun (f : Parameter.field_view) -> f.name = path) p.fields with
                      | Some i -> Some (p.path, if List.length p.fields = 3 then [ i ] else [])
                      | None ->
                          (* a vector's component row is named [row.axis] *)
                          Option.map (fun i -> p.path, [ i ])
                            (List.find_index (fun axis -> p.path ^ "." ^ axis = path) [ "x"; "y"; "z" ])
                          |> fun found -> if List.length p.fields = 3 then found else None) parameters in
                    (match expression_text text, key_sub with
                     | Ok expr, Some (key, sub) -> Some (Object_arg { node = node_id; key; sub; expr })
                     | Error message, _ -> Some (Declined message)
                     | Ok _, None -> None)
                | Pinned _ | Split _ | Reset _ -> None) edits))) in
          None, changes, [], value.live_cook) in
    (* an inspector shows the pane in use, or the graph panel its [:of] names; one of another pane
       only shows (a press there makes that pane the one in use first) *)
    let inspectors = List.map (fun ((leaf : Pxui_shell.Layout.leaf), root) ->
      let pane = pane_of (panel_key value.doc leaf.path, leaf.path, leaf.panel, `List) in
      if in_use pane then leaf, inspect (value, scope_view, selection, scope_active) root leaf.body
      else
        let shown = graph_shown && stored_projection pane = Graph_view && graph_name pane <> None in
        let panel, _, _, _ = inspect (pane, pane.scope_view, pane.selection, shown) root leaf.body in
        leaf, (panel, [], [], value.live_cook))
      (of_kind Pxui_shell.Layout.Inspector) in
    let panel = match List.find_opt (fun ((l : Pxui_shell.Layout.leaf), _) ->
        focus = Inspector && Some l.path = focus_path) inspectors, inspectors with
      | Some (_, (panel, _, _, _)), _ | None, (_, (panel, _, _, _)) :: _ -> panel
      | None, [] -> None in
    let inspector_changes = List.concat_map (fun (_, (_, changes, _, _)) -> changes) inspectors
    and settings_changes = List.concat_map (fun (_, (_, _, changes, _)) -> changes) inspectors
    and live_cook = Option.value ~default:value.live_cook
      (List.find_map (fun (_, (_, _, _, live)) -> if live <> value.live_cook then Some live else None) inspectors) in
    let changes = changes @ inspector_changes @ layout_changes in
    let scope_changes = scope_changes @ !workspace_moves in
    (* every timeline leaf, else the strip under the tree *)
    let timeline_slots = match of_kind Timeline with
      | [] -> Option.to_list (Option.map (fun (_, box) -> g.timeline_at, box, true) timeline_root)
      | leaves -> List.map (fun ((l : Pxui_shell.Layout.leaf), box) -> l.body, box, false) leaves in
    let timeline_intents = List.concat_map (fun (((_, _, _, height) as bounds), box, edge) ->
      if height <= 0 then [] else
      Pxui.Ui.within ui box (fun () ->
        Pxui_shell.Timeline_bar.draw ui ~bounds ~edge
          ~playing:(Sketch_support.Timeline.mode timeline = Sketch_support.Timeline.Playing)
          ~frame:(Sketch_support.Timeline.frame timeline)
          ~time:(Sketch_support.Timeline.time timeline)
          ~max_frame:value.timeline_frames ())) timeline_slots in
    (* a lowered node is edited through its text: the handles of the node selected in the
       graph pane write its arguments, the list's rows of a geometry object have none *)
    let scope_target = if scope_active then scope_node value else None in
    let handle_target = match scope_target with
      | Some (_, node) -> Some node
      | None -> if lowered_level then None else selected in
    let handle_edits, grab, picked = match active with
      | Some leaf when visible workspace leaf.Pxui_shell.Layout.panel ->
          Pxui.Ui.within ui view_root (fun () ->
            view_handles ui ~selected:handle_target ~space:(space { value with selection })
              ~bounds:leaf.body)
      | _ -> [], false, None in
    let selection = match picked with
      | Some id when value.level = Document.Scene -> Selection.select id selection
      | Some _ | None -> selection in
    let handle_ops, handle_changes = match scope_target, handle_target, handle_edits with
      | Some (path, node), _, _ :: _ ->
          let parameters = Result.value ~default:[] (Flow_sop.Port.parameters (Node.parameter_fields node)) in
          List.filter_map (fun (p : Flow_sop.Port.parameter) ->
            if List.exists (fun (f : Parameter.field_view) -> List.mem_assoc f.name handle_edits) p.fields
            then Some (Syntax_edit (Flow_sop.Flow_edit.Set_arg { node = path;
              key = Flow_sop.Flow_edit.Kw p.path; sub = [];
              value = Editor_document.Scene_sync.value_syntax (List.map (fun (f : Parameter.field_view) ->
                match List.assoc_opt f.name handle_edits with
                | Some current -> { f with current } | None -> f) p.fields) }))
            else None) parameters, None
      | _, Some node, _ :: _ -> [], Some (Node.id node, handle_edits)
      | _ -> [], None in
    let changes = changes @ handle_ops in
    let context = match leader with
      | Leader.Pending _ -> Editor_core.Guide_context.Leader
      | Idle when value.prompt <> None || menu <> None
          || Pxui_graph.Scope.editing scope_view -> Search
      | Idle when listing -> List
      | Idle -> (match (if scope_active then Pxui_graph.Scope.selected scope_view
                        else List.map (fun id -> [ string_of_int id ]) (Selection.selected_nodes selection)) with
          | [] -> Canvas | [_] -> Node | _ -> Multi) in
    let hide_guide = status_box { value with workspace; status_fps; selection; guide; focus; leader }
        ui frame ~render_status ~error_status ~context in
    (* echo, the sheet's [08]: messages only (saved, undo and redo results, refusals), never a key
       press; the last one fades after 3 seconds.  It stands at the bottom-left of the focused pane,
       above the strip. *)
    (match value.notice with
     | Some (kind, text) when frame.time -. value.notice_at < 3. ->
         let bounds = match List.find_opt (fun ((l : Pxui_shell.Layout.leaf), _) -> Some l.path = header_focus) roots with
           | Some (l, _) -> l.body | None -> graph_body in
         let rec cards (s : Flow_sop.Projection.scope) = List.concat_map (fun (n : Flow_sop.Projection.node) ->
           Option.to_list (Pxui_graph.Scope.Private.box_of scope_view n.path)
           @ (match n.zone with Some z -> cards z.scope | None -> [])) s.nodes in
         let avoid = match value.scope_key with
           | Some k when scope_active -> cards k.scope | _ -> [] in
         Pxui_shell.Status_bar.tips ui ~bounds ~avoid
           [ text, (match kind with Info -> `Info | Refusal -> `Refusal) ]
     | _ -> ());
    let pane_roots = List.map (fun ((l : Pxui_shell.Layout.leaf), box) -> (l.panel, Some l.path), box) roots
      @ Option.to_list (Option.map (fun (panel, box) -> (panel, None), box) timeline_root) in
    let focus, focus_path = List.fold_left (fun (latest, focus) (target, box) ->
      match (Pxui.Ui.signal ui box).subtree_press with
      | Some index when index >= latest -> index, target
      | _ -> latest, focus) (-1, (focus, focus_path)) pane_roots
      |> snd in
    (* a focus whose leaf an edit split, retyped or moved follows it, so the next panel key acts *)
    let focus, focus_path = match focus_path with
      | None -> focus, focus_path
      | Some _ -> (match focused_leaf (geometry value workspace frame) focus focus_path with
          | Some leaf -> leaf.panel, Some leaf.path
          | None -> focus, focus_path) in
    let pane_keys = List.map (fun (target, box) -> Pxui.Ui.key box, target) pane_roots in
    (* The gutters last, on top of every pane's hit area: a drag applies from the next frame. *)
    let grips = Pxui_shell.Chrome.splitters ~state:(panel_state value) ~hidden:workspace.hidden (shell_tree value workspace) ui
           shortcut_frame in
    let drops = Pxui_shell.Chrome.drop_targets ui ~geometry:g ~state:(panel_state value)
      ~dragging:(List.find_map (function Pxui_shell.Chrome.Dragging (path, released) -> Some (path, released) | _ -> None) intents) in
    let workspace, drag_changes = layout_intents vw workspace (grips @ drops) in
    let workspace = match workspace.window_live with
      | None -> workspace
      | Some _ when List.exists (function Pxui_shell.Chrome.Window_drag _ -> true | _ -> false)
          (intents @ grips) -> workspace
      | Some _ -> { workspace with window_live = None } in
    (* a gutter drag that ended without its release (the window lost the focus, the pointer was
       cancelled) leaves no size behind for the next click on a gutter to commit *)
    let workspace = match workspace.live with
      | Some _ when not (List.exists (function Pxui_shell.Chrome.Resize _ | Settled -> true | _ -> false) grips)
          && (not (Frame.mouse_down Input.LeftButton frame) || Frame.has_event (function
               | Event.WindowFocusLost | Event.PointerCancelled Input.LeftButton -> true | _ -> false) frame) ->
          { workspace with live = None }
      | _ -> workspace in
    let changes = changes @ drag_changes in
    { workspace; focus; focus_path; pane_keys; outline; outline_intents; selection; menu; menu_pick; scope_view; scope_changes; tree; document = (network value).graph;
      edit_error = value.edit_error;
      effects = Parameter.no_effects;
      timeline_intents; frame_request = initial_frame_request; prompt = None; prompt_intent = None;
      panel; grab; settings = unchanged;
      opened = None; live_cook; label = "Edit";
      changes; tree_intents = list_intents; text_intents; open_graph;
      settings_changes; graph_panes; locals; other_texts;
      handle_changes; hide_guide } in
  let leader_panel = match leader with
    | Leader.Pending prefix -> Some (fun ui ->
        Pxui_shell.Which_key.panel ui ~category:Leader.group ~describe:Leader.describe_prefix ~order:Leader.order keymap ~prefix
          ~focus:(Leader.scope focus) ~focus_name:(Leader.pane_name focus))
    | Idle -> None in
  (* Presets: Space s names and saves the document, Space b browses, loads
     (Enter), and deletes (Delete twice). A load replaces the document below
     as one undo entry. *)
  let initial_prompt = List.fold_left (fun prompt -> function
    | Leader.Save_preset -> Some (Saving (Preset.default_name ()))
    | Browse_presets ->
        browse value ""
    | Guide_keys -> Some Keys
    | Command_palette -> Some (Palette "")
    | Jump -> Some (Jumping "")
    | _ -> prompt) value.prompt actions in
  let prompt_panel ui prompt =
    let module Ui = Pxui.Ui in
    let next = match prompt with
    | None -> None, None
    | Some Keys ->
        let commands = List.filter (fun (command : Leader.command) -> match command.action with
          | List_command _ | Frame_tile -> false | _ -> true) value.keymap in
        let context = String.lowercase_ascii (Leader.pane_name focus) ^ " focused" in
        (if Pxui_shell.Which_key.sheet ui ~context ~category:Leader.sheet_group commands then Some Keys else None), None
    | Some (Saving name) ->
        (match Pxui_shell.Prompt.name ui ~key:"preset-save"
            ~title:"Save preset" ~description:"Name for the current state of the document"
            ~label:"Preset name" ~query:name with
         | None | Some (_, `Cancel) -> None, None
         | Some (name, `Submit) -> None, Some (Save_preset_file name)
         | Some (name, _) -> Some (Saving name), None)
    | Some (Making_macro m) ->
        (match Pxui_shell.Prompt.macro ui ~key:"make-macro" ~title:"Make a macro from the selection"
            ~literals:(Array.of_list (List.map (fun (_, e) -> Flow.Lisp.flat e) m.draft.literals))
            ~free:m.draft.free m.state with
         | None -> None, None
         | Some (state, `Submit) ->
             None, Some (Edit_source (Flow_sop.Flow_edit.macro_op m.draft ~nodes:m.nodes
               ~name:state.name state.holes))
         | Some (state, `None) -> Some (Making_macro { m with state }), None)
    | Some (Browsing { query; presets; last_state }) ->
        let entries query = (Option.fold ~none:[]
          ~some:(fun time -> ["Last edited state", time, true]) last_state
          @ List.map (fun (name, time) -> name, time, false) presets)
          |> List.filter (fun (name, _, _) -> Ui.fuzzy_match ~query name) |> Array.of_list in
        let rows query = entries query |> Array.map (fun (name, time, recovery) ->
            let tm = Unix.localtime time in
            name, Printf.sprintf "%s%02d-%02d %02d:%02d" (if recovery then "Autosave · " else "")
              (tm.tm_mon + 1) tm.tm_mday tm.tm_hour tm.tm_min) in
        (match Pxui_shell.Prompt.search ui ~key:"preset-browse"
            ~title:(Printf.sprintf "Presets · %d" (Array.length (entries "")))
            ~label:"Search presets" ~query ~rows with
         | None | Some (_, `Cancel) -> None, None
         | Some (query, `Pick index) ->
             let name, _, recovery = (entries query).(index) in
             None, Some (if recovery then Load_last_state else Load_preset_file name)
         | Some (query, `Delete index) ->
             let name, _, recovery = (entries query).(index) in
             Some (Browsing { query; presets; last_state }),
             Some (if recovery then Delete_last_state query else Delete_preset_file { name; query })
         | Some (query, _) -> Some (Browsing { query; presets; last_state }), None)
    | Some (Jumping query) ->
        (* every graph, grouped like the outline *)
        let all = Navigator.jump_rows (fst value.doc.Document.workspace).checked in
        let matches query = List.filter (fun (name, _) -> Ui.fuzzy_match ~query name) all in
        let rows query = Array.of_list (matches query) in
        (match Pxui_shell.Prompt.search ui ~key:"graph-jump"
            ~title:"Jump to graph" ~label:"Search graphs" ~query ~rows with
         | None | Some (_, `Cancel) -> None, None
         | Some (query, `Pick index) -> None, Some (Go (fst (List.nth (matches query) index)))
         | Some (query, _) -> Some (Jumping query), None)
    | Some (Palette query) ->
        (* Every keymap command once per id (undo has several chords). *)
        let commands = List.fold_left (fun seen (command : Leader.command) ->
            if command.scope <> None && command.scope <> Some (Leader.scope focus) then seen else
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
        let prompt_intent = match prompt_intent, !bar_action with
          | None, Some action -> Some (Run_action action) | intent, _ -> intent in
        { result with prompt; prompt_intent }) with
    | Some result -> result
    | None ->
      { workspace; focus; focus_path; pane_keys = []; graph_panes = value.graph_panes; locals = value.locals; other_texts = []; outline = value.outline; outline_intents = []; selection; menu; menu_pick = None; scope_view; scope_changes = scope_command_changes; tree; document = (network value).graph;
        edit_error = value.edit_error;
        effects = Parameter.no_effects; timeline_intents = [];
        frame_request = initial_frame_request; prompt = initial_prompt;
        prompt_intent = None; panel = None; grab = false;
        settings = value.doc.settings;
        opened = None; live_cook = value.live_cook; label = "Edit";
        changes = command_changes; tree_intents = list_intents;
        text_intents = []; open_graph;
        settings_changes = []; handle_changes = None; hide_guide = false } in
  let result = match result.prompt_intent with
    | Some (Edit_source op) -> { result with changes = result.changes @ [ Syntax_edit op ] }
    | _ -> result in
  (* A payload in flight: what the panes saw under the pointer becomes the carry's report, and
     nothing else edits the document until the put (navigation and selection only). *)
  let carry_report = if not carrying then None else begin
    let place_of_path = function [ graph ] -> Carry.Graph graph | path -> Carry.Node path in
    let scope = List.filter_map (function
      | Pxui_graph.Scope.Drop_over { path; _ } -> Some (place_of_path path, false)
      | Dropped { path; _ } -> Some (place_of_path path, true)
      | _ -> None) result.scope_changes in
    let text_drops (text : Text_pane.state) (shown : Text_pane.shown) intents = List.filter_map (function
      | Text_pane.Carry_over (byte, dropped) ->
          let drafted = match text.tab with
            | Text_pane.Document -> text.draft <> None
            | Graph -> (match text.graph_draft with Some (g, _) -> g = shown.graph | None -> false)
            | Selection -> (match text.binding_draft with Some (p, _) -> p = shown.key | None -> false) in
          let target = if drafted then Carry.Drafted else match text.tab with
            | Document -> Carry.Whole | Graph -> Graph_text shown.graph | Selection -> Selection_text shown.key in
          Some (Carry.Text { target; text = shown.text; byte }, dropped)
      | _ -> None) intents in
    let text_drops = Option.fold ~none:[] ~some:(fun shown -> text_drops text shown result.text_intents) text_shown
      @ List.concat_map (fun (key, shown, intents) -> text_drops (local_of { value with locals = result.locals } key).code shown intents)
          result.other_texts in
    match scope @ text_drops @ List.rev !inspector_drops @ List.rev !viewport_drops with
    | (over, dropped) :: _ -> Some { over; dropped }
    | [] -> None
  end in
  let result = if not carrying then result else
    { result with changes = []; handle_changes = None; settings_changes = []; text_intents = [];
      other_texts = []; menu_pick = None;
      tree_intents = List.filter (function Pxui_shell.Tree.Select _ -> true | _ -> false) result.tree_intents;
      scope_changes = List.filter (function
        | Pxui_graph.Scope.Selected _ | Activated _ | Drop_over _ | Dropped _ | Notice _ -> true
        | _ -> false) result.scope_changes;
      prompt_intent = (match result.prompt_intent with Some (Go _ as intent) -> Some intent | _ -> None) } in
  let guide = guide && not result.hide_guide in
  let guide_error = if guide = value.guide then None else
    match save_guide value.preferences guide with
    | Ok () -> None | Error message -> Some (Refusal, "Guide preference not saved: " ^ message) in
  (* The one reduction phase: panes have finished constructing their boxes. *)
  let document, edit_error, editor_effects = List.fold_left apply_change
      ((network value).graph, value.edit_error, Parameter.no_effects) result.changes in
  let document, selection, tree, opened, tree_label, _ = List.fold_left
      (apply_tree value) (document, result.selection, result.tree, result.opened, None, rows)
      result.tree_intents in
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
    | Inside _ | Scene -> { effects with Parameter.cook = false } in
  let label = match List.find_map intent_label result.changes, tree_label with
    | Some label, _ | None, Some label -> label
    | None, None when settings != value.doc.settings -> "Settings"
    | None, None -> match result.handle_changes with
      | Some (id, _) ->
          "Edit " ^ Option.fold ~none:(string_of_int id) ~some:Node.label
            (Edit_graph.find document.geometry ~node_id:id)
      | None -> "Edit" in
  let result = { result with document; selection; tree; opened; edit_error;
    effects = Parameter.union_effects (node_effects
      (Parameter.union_effects editor_effects parameter_effects)) settings_effects;
    settings; label } in
  let timeline, timeline_changes = List.fold_left (fun (timeline, changes) intent ->
    let next, emitted = match intent with
      | Pause_toggle -> Sketch_support.Timeline.toggle_pause timeline
      | Stop_playback -> Sketch_support.Timeline.stop timeline
      | Reset_playback -> Sketch_support.Timeline.reset timeline
      | Seek_playback frame -> Sketch_support.Timeline.seek timeline ~frame
      | Set_end _ -> timeline, [] in
    next, changes @ emitted) (timeline, timeline_changes) result.timeline_intents in
  (* the End field of a tall timeline: the scrub range (view state, like the playhead) *)
  let value = { value with timeline_frames = List.fold_left (fun frames -> function
    | Set_end last -> max 1 last | _ -> frames) value.timeline_frames result.timeline_intents } in
  let prompt, notice, loaded = match result.prompt_intent with
    | None -> result.prompt, (match List.find_map (function
        | Notice message -> Some (Info, message) | Declined message -> Some (Refusal, message)
        | _ -> None) result.changes with
        | Some _ as notice -> notice | None -> value.notice), None
    | Some (Run_action _ | Edit_source _ | Go _) -> result.prompt, value.notice, None
    | Some (Save_preset_file name) ->
        let notice = match Preset.save ~directory:value.presets ~name
            ~doc:value.doc ~view:(view_state result.panel) with
          | Ok path -> Info, "Saved preset " ^ Filename.basename path
          | Error message -> Refusal, "Preset not saved: " ^ message in
        result.prompt, Some notice, None
    | Some ((Load_preset_file _ | Load_last_state) as intent) ->
        let path, restored = match intent with
          | Load_preset_file name -> Preset.path ~directory:value.presets ~name, "Loaded preset " ^ name
          | _ -> state_file value, "Restored last edited state" in
        let rejected = if intent = Load_last_state then "Last edited state rejected: " else "Preset rejected: " in
        (match Preset.load ~path
            ~factories:value.factories ~settings:value.doc.settings with
         | Ok preset -> result.prompt, Some (Info, restored), Some preset
         | Error message -> result.prompt, Some (Refusal, rejected ^ message), None)
    | Some ((Delete_preset_file _ | Delete_last_state _) as intent) ->
        let directory, name, query, description = match intent with
          | Delete_preset_file {name; query} -> value.presets, name, query, "preset " ^ name
          | Delete_last_state query -> state_directory value, value.state_name, query, "last edited state"
          | _ -> assert false in
        let notice = match Preset.delete ~directory ~name with
          | Ok () -> Info, "Deleted " ^ description
          | Error message -> Refusal, "Preset not deleted: " ^ message in
        browse value query,
        Some notice, None in
  (* [m] in the workspace pane: the make-macro dialog over the selection, its first two
     literals ticked as in the study. *)
  let prompt, notice = match List.find_map (function
      | Pxui_graph.Scope.Macro_requested nodes -> Some nodes | _ -> None) result.scope_changes with
    | Some nodes ->
        (match Flow_sop.Flow_edit.macro_draft (fst value.doc.Document.workspace).source nodes with
         | Ok draft ->
             Some (Making_macro { nodes; draft; state = { name = draft.name;
               holes = Array.of_list (List.mapi (fun i _ -> i < 2, "p" ^ string_of_int (i + 1)) draft.literals) } }),
             notice
         | Error d -> prompt, Some (Refusal, d.Flow.Diagnostic.message))
    | None -> prompt, notice in
  (* Shared undo stack: every document change (a parameter, a workspace gesture, an
     inspector commit) becomes one history entry; Command/Ctrl-Z undoes,
     Shift-Command/Ctrl-Z or Ctrl-Y redoes. *)
  let present = value.doc in
  let current = network value in
  let next = match loaded with
    | Some (preset : Preset.loaded) -> preset.doc
    | None ->
        let edited = if result.document == current.graph then current
          else { current with graph = result.document;
            displayed = Document.displayed_of ?previous:current.displayed result.document
              current.displayed } in
        let doc = if edited == current then present
          else Document.with_network present value.level edited in
        let doc = if value.level = Document.Scene && edited != current then Document.prune doc else doc in
        if result.settings == doc.settings then doc
        else { doc with settings = result.settings } in
  (* Enter and row activation share camera selection and look-through. *)
  let entered_camera = if value.level <> Document.Scene || Option.is_some loaded || carrying then None
    else
      let candidate = match result.opened with
        | Some _ as id -> id
        | None when List.mem Leader.Enter actions -> Selection.selected result.selection
        | None -> None in
      match candidate with
      | Some id when kind value id = Some "camera" && view_wants value `Primary id -> Some id
      | _ -> None in
  let next = match entered_camera with
    | Some id when next.active_camera <> Some id -> { next with active_camera = Some id }
    | _ -> next in
  (* the scene and World edits above act on derived objects: each difference is written to
     the text (a refused one changes nothing) *)
  let edit_note = ref None in
  let reconciled ~before next result =
    match Doc.reconcile ~factories:value.factories before next with
    | Ok doc ->
        Option.iter (fun note -> edit_note := Some note) (Editor_document.Scene_sync.note before next);
        doc, result
    | Error message ->
        before, { (result : _ frame_result) with edit_error = Some message } in
  let next, result = if Option.is_some loaded then next, result else
    reconciled ~before:present next result in
  (* Workspace gestures: one rewrite of the source per gesture, lowered into
     the document, one history entry named by the op. *)
  let added = ref [] and created = ref None and renamed = ref None in
  (* a frame's gestures land together: the first one refused leaves none of them applied, and a
     later one cannot hide its message *)
  let refused = ref None in
  let gestures = next, result in
  let next, result = if Option.is_some loaded then next, result else
    List.fold_left (fun ((next : Document.t), result) change ->
      let refuse message = refused := Some message; next, result in
      if !refused <> None then next, result else match change with
      | Dock_panels (source, target, side) ->
          (match dock_panels ~factories:value.factories next source target side with
           | Ok doc -> doc, { (result : _ frame_result) with label = "Arrange panel"; edit_error = None }
           | Error message -> refuse message)
      | Panel_state (path, state) ->
          let key = panel_key next path in
          let doc = Doc.layout_edit next (fun layout ->
            { layout with panels = Layout_by_path.Path_map.add key state layout.panels }) in
          doc, { (result : _ frame_result) with label =
            (if state.collapsed then "Collapse panel" else "Arrange panel"); edit_error = None }
      | Select_layout name when Option.map (fun (g : Flow.Workspace.graph) -> g.name)
          (Workspace_doc.editor_graph (fst next.workspace)) = Some name -> next, result
      | Select_layout name ->
          (match Doc.select_layout ~factories:value.factories next name with
           | Ok doc -> doc, { (result : _ frame_result) with label = "Switch layout"; edit_error = None }
           | Error message -> refuse message)
      | Syntax_edit op ->
          (match Doc.syntax_edit ~factories:value.factories next op with
           | Ok doc ->
               (match op with
                | Flow_sop.Flow_edit.Add_node { scope; name; _ } -> added := [ scope @ [ name ] ]
                | Rename_graph { name; to_ } -> renamed := Some (name, to_)
                | Duplicate { nodes } ->
                    added := Flow_sop.Flow_edit.duplicated (fst next.workspace).source nodes
                | _ -> ());
               if !edit_note = None then
                 edit_note := Option.map (fun words -> "Wrote " ^ words) (Echo.words op);
               doc, { (result : _ frame_result) with label = Flow_sop.Flow_edit.label op; edit_error = None;
               effects = Parameter.union_effects result.effects Doc.cook_effects }
           | Error message -> refuse message)
      | Syntax_batch (label, ops) ->
          (match Doc.syntax_batch ~factories:value.factories next ops with
           | Ok doc ->
               List.iter (function
                 | Flow_sop.Flow_edit.Add_node { scope; name; _ } -> added := [ scope @ [ name ] ]
                 | Set_graph { name; _ } when label = "New material" -> created := Some name
                 | _ -> ()) ops;
               if !edit_note = None then
                 edit_note := Option.map (fun words -> "Wrote " ^ words) (Echo.batch ops);
               doc, { (result : _ frame_result) with label; edit_error = None;
                 effects = Parameter.union_effects result.effects Doc.cook_effects }
           | Error message -> refuse message)
      | Pin_row { node; label; pin } ->
          let module PM = Layout_by_path.Path_map in
          let module SM = Layout_by_path.String_map in
          let doc = Doc.layout_edit next (fun l ->
            let rows = Option.value ~default:SM.empty (PM.find_opt node l.rows) in
            let rows = match pin with Some v -> SM.add label v rows | None -> SM.remove label rows in
            { l with rows = if SM.is_empty rows then PM.remove node l.rows else PM.add node rows l.rows }) in
          doc, { (result : _ frame_result) with label = (match pin with
            | Some false -> "Unpin row from card" | _ -> "Pin row to card"); edit_error = None }
      | Object_arg { node; key; sub; expr } ->
          (* the expression typed in a row is the argument of the call that holds the object (of a
             loop's template: every copy changes) *)
          let ( let* ) = Result.bind in
          let home = match value.level with
            | Document.Scene -> List.assoc_opt node next.Document.homes.objects
            | Inside _ -> List.assoc_opt node next.homes.layers in
          (match home with
           | None -> refuse "That object is not in the text yet: change one of its values, which writes it."
           | Some home ->
               let op path = Flow_sop.Flow_edit.Set_arg { node = path; key = Kw key; sub; value = expr } in
               (match (let* doc, path = Editor_document.Scene_sync.bind_home ~factories:value.factories next home in
                       Doc.syntax_edit ~factories:value.factories doc (op path)) with
                | Ok doc ->
                    edit_note := Editor_document.Scene_sync.template_note next home;
                    doc, { result with label = "Edit expression";
                      effects = Parameter.union_effects result.effects Doc.cook_effects }
                | Error message -> refuse message))
      | Syntax_inline { home; key; make } ->
          (* bind what is written in place (the call holding it, then the expression), then
             the gesture on its name *)
          let ( let* ) = Result.bind in
          let bound =
            let* doc, node = Editor_document.Scene_sync.bind_home ~factories:value.factories next home in
            let* doc = Doc.syntax_edit ~factories:value.factories doc
              (Flow_sop.Flow_edit.Unfold { node; key; sub = [] }) in
            (match Flow_sop.Flow_edit.arg_text (fst doc.workspace).source node key with
             | Some { Flow.Syntax.node = Sym name; _ } ->
                 let path = List.rev (name :: List.tl (List.rev node)) in
                 let* doc = Doc.syntax_edit ~factories:value.factories doc (make path) in
                 Ok (doc, make path)
             | _ -> Error "The panel could not be named.") in
          (match bound with
           | Ok (doc, op) ->
               doc, { (result : _ frame_result) with label = Flow_sop.Flow_edit.label op;
                 effects = Parameter.union_effects result.effects Doc.cook_effects }
           | Error message -> refuse message)
      | _ -> next, result) (next, result) result.changes in
  let next, result = match !refused with
    | None -> next, result
    | Some _ as edit_error ->
        added := []; created := None; renamed := None;
        fst gestures, { (snd gestures : _ frame_result) with edit_error } in
  (* The workspace pane's layout gestures: moving an item and collapsing a zone
     edit the layout keys (one history entry each); the probe is view state and
     never reaches history. *)
  let module M = Layout_by_path.Path_map in
  (* a node added from the menu lands where the menu was opened *)
  let scope_changes = match !added, result.menu_pick, value.menu with
    | [ path ], Some _, Some menu ->
        let scope = List.filteri (fun i _ -> i < List.length path - 1) path in
        let mx, my = Pxui_graph.Node_menu.position menu in
        (match Pxui_graph.Scope.scope_point value.scope_view ~scope (float mx, float my) with
         | Some (x, y) -> Pxui_graph.Scope.Moved [ path, x, y ] :: result.scope_changes
         | None -> result.scope_changes)
    | _ -> result.scope_changes in
  let next, result, probes = if Option.is_some loaded then next, result, value.probes else
    List.fold_left (fun (next, result, probes) -> function
      | Pxui_graph.Scope.Zone_collapsed { zone; collapsed } ->
          Doc.layout_edit next (fun l -> { l with collapsed =
            if collapsed then M.add zone true l.collapsed else M.remove zone l.collapsed }),
          { (result : _ frame_result) with label = if collapsed then "Collapse zone" else "Expand zone" }, probes
      | Moved placed ->
          Doc.layout_edit next (fun l -> { l with at = List.fold_left (fun at (path, x, y) ->
            M.add path (x, y) at) l.at placed }),
          { result with label = (if !added = [] then "Move" else result.label) }, probes
      | Level_set changes ->
          Doc.layout_edit next (fun l -> List.fold_left (fun (l : Layout_by_path.t) (path, level, pinned) ->
            { l with
              level = (match level with Some v -> M.add path v l.level | None -> M.remove path l.level);
              pinned = if pinned then M.add path true l.pinned else M.remove path l.pinned }) l changes),
          { result with label = "Detail level" }, probes
      | Probe_set { zone; index } -> next, result, M.add zone index probes
      | Frames_set { scope; frames } ->
          Doc.layout_edit next (fun l -> { l with frames =
            if frames = [] then M.remove scope l.frames
            else M.add scope (List.map (fun (title, at, size) -> { Layout_by_path.title; at; size }) frames) l.frames }),
          { result with label = "Frame" }, probes
      | Display_set path ->
          (match path with
           | [ graph; name ] when name <> "@result" ->
               let op = Flow_sop.Flow_edit.Connect { node = [ graph; "@result" ]; key = Whole; src = name; iter = false } in
               (match Doc.syntax_edit ~factories:value.factories next op with
                | Ok doc ->
                    doc, { (result : _ frame_result) with label = "View node"; edit_error = None;
                      effects = Parameter.union_effects result.effects Doc.cook_effects }, probes
                | Error message ->
                    next, { (result : _ frame_result) with edit_error = Some message }, probes)
           | [ graph; "@result" ] ->
               let doc = Doc.layout_edit next (fun l ->
                 { l with display = M.remove [ graph ] l.display }) in
               doc, { (result : _ frame_result) with label = "View node"; edit_error = None;
                 effects = Parameter.union_effects result.effects Doc.cook_effects }, probes
           | graph :: _ ->
               (* a node inside a loop cannot be the graph's result: the layout marks it as the one shown,
                  at the iteration the selectors probe; v on it again goes back to the result *)
               let doc = Doc.layout_edit next (fun l -> { l with display =
                 if M.find_opt [ graph ] l.display = Some path then M.remove [ graph ] l.display
                 else M.add [ graph ] path l.display }) in
               doc, { (result : _ frame_result) with label = "View node"; edit_error = None;
                 effects = Parameter.union_effects result.effects Doc.cook_effects }, probes
           | [] -> next, result, probes)
      | Syntax_edit _ | Selected _ | Notice _ | Macro_requested _ | Defn_requested _
      | Copy_requested _ | Paste_requested | Menu_requested _ | Activated _ | Drop_over _ | Dropped _ ->
          next, result, probes)
      (next, result, value.probes) scope_changes in
  let before_world = next in
  let next, world_label = if in_world value
    then world_keys value next result.selection actions else next, None in
  (* Space e opens the World, creating the singleton on first use. *)
  let next, world_added = match Objects.ids "world" next.scene.graph.geometry with
    | [] when List.mem Leader.Go_world actions ->
        (match add_world next daylight with Ok doc -> doc, true | Error _ -> next, false)
    | _ -> next, false in
  let next, result = if Option.is_some loaded then next, result
    else reconciled ~before:before_world next result in
  let is_view = function Pxui_shell.Layout.View _ -> true | _ -> false in
  let owner = match List.find_opt (fun (_, (panel, _)) -> panel = result.focus && is_view panel)
      result.pane_keys with
    | Some (key, _) -> Some key
    | None -> List.find_map (fun (key, (panel, _)) -> if is_view panel then Some key else None)
        result.pane_keys in
  let input = Pxui.Ui.input ?owner value.ui in
  let dragging = Frame.mouse_down Input.LeftButton frame || Frame.has_event (function
    | Event.MouseReleased (Input.LeftButton, _) -> true | _ -> false) frame in
  let gesture = if not dragging || Option.is_some loaded
      || world_added || world_label <> None then None else
    match List.find_map (function
      | Set_parameter { node; path; _ } ->
          Some (Printf.sprintf "graph.scrub:%s:%d:%s" (level_key value.level) node path)
      | Syntax_edit op -> Flow_sop.Flow_edit.gesture op
      | Panel_state (path, _) -> Some ("panel:" ^ String.concat "/" (panel_key value.doc path))
      | Dock_panels (path, _, _) -> Some ("panel:" ^ String.concat "/" (panel_key value.doc path))
      | _ -> None) result.changes with
    | Some key -> Some key
    | None ->
    let graph = List.filter_map (function
      | change when intent_label change <> None -> Some []
      | _ -> None) result.changes in
    match graph, result.tree_intents, result.handle_changes,
        result.settings_changes with
    | [], [], Some (id, changes), [] ->
        Some (parameter_gesture "handle" value.level id changes)
    | [], [], None, (_ :: _ as changes) ->
        Some (parameter_gesture "settings" value.level (-1) changes)
    | [], (Pxui_shell.Tree.Flag { column; _ } :: _ as intents), None, []
      when List.for_all (function Pxui_shell.Tree.Flag _ -> true | _ -> false) intents ->
        (* a stroke down a flag column of the list is one entry *)
        Some (Printf.sprintf "list.flag:%s:%d" (level_key value.level) column)
    | _ -> None in
  let history = if next == present then value.history
    else commit
        ~label:(if result.prompt_intent = Some Load_last_state && Option.is_some loaded then "Restore last edited state"
          else if Option.is_some loaded then "Load preset"
          else if world_added then "Add World"
          else if world_label <> None then Option.get world_label
          else result.label)
        ~merge:(if List.exists (function Syntax_edit (Flow_sop.Flow_edit.Set_layout _) -> true | _ -> false) result.changes
          then Editor_core.History.Burst { key = "layout"; at = frame.Frame.time; window = 1.5 }  (* keys: no drag seals it *)
          else Option.fold ~none:Editor_core.History.Step
            ~some:(fun key -> Editor_core.History.Gesture key) gesture) next value.history in
  let stepped = if List.mem Leader.Redo actions then Editor_core.History.redo history
    else if List.mem Leader.Undo actions then Editor_core.History.undo history else None in
  let notice = match stepped with
    | None when List.mem Leader.Redo actions -> Some (Refusal, "Redo: nothing to redo")
    | None when List.mem Leader.Undo actions -> Some (Refusal, "Undo: nothing to undo")
    | None -> notice
    | Some _ when List.mem Leader.Redo actions ->
        Option.map (fun label -> Info, "Redo " ^ label) (Editor_core.History.redo_label history)
    | Some _ -> Some (Info, "Undo " ^ Editor_core.History.label history) in
  let history, doc, undone = match stepped with
    | Some history -> history, Editor_core.History.present history, true
    | None -> history, (if carrying then value.doc else Editor_core.History.present history), false in
  let effects = if undone || Option.is_some loaded || carry_changed
    then Parameter.union_effects result.effects Doc.cook_effects else result.effects in
  (* The open level must still exist after undo or a preset load. *)
  let level = Document.resolve_level doc
      (if Option.is_some loaded then Document.Scene else value.level) in
  let value' = { value with doc; level; workspace = unrestore value.doc doc result.workspace } in
  (* the selection keeps the nodes that still exist in the open network *)
  let selection =
    if level <> value.level || Option.is_some loaded then Selection.empty
    else
      let exists id = Edit_graph.find (network value').graph.geometry ~node_id:id <> None in
      match List.filter exists (Selection.selected_nodes result.selection) with
      | ids when ids = Selection.selected_nodes result.selection -> result.selection
      | ids -> Selection.select_nodes ids result.selection in
  (* Entering and leaving levels: i / double-click / list activation, u. *)
  (* i also follows a reference of the node selected in the pane (a material, an object's graph) *)
  let followed = match List.find_map (function
      | Pxui_graph.Scope.Activated path -> Some path | _ -> None) result.scope_changes with
    | Some path -> follow_target ~path value
    | None when List.mem Leader.Enter actions ->
        (match follow_target value with Some _ as found -> found | None -> viewport_target value)
    | None -> None in
  let target = match List.find_opt (function
      | Leader.Enter | Up | Go_world -> true | _ -> false) actions, result.opened with
    | _ when followed <> None -> None
    | Some Leader.Up, _ when value.back <> [] -> None
    | Some Leader.Up, _ -> (match level with
      | Inside _ -> Some Document.Scene
      | Scene -> None)
    | Some Leader.Go_world, _ ->
        Option.map (fun id -> Document.Inside id)
          (List.find_opt (enterable value') (Objects.ids "world" doc.scene.graph.geometry))
    | Some Leader.Enter, _ | _, Some _ ->
        let candidate = match result.opened with
          | Some id -> Some id | None -> Selection.selected selection in
        (match level, candidate with
         | Document.Scene, Some id when enterable value' id -> Some (Document.Inside id)
         | _ -> None)
    | _ -> None in
  let selection = match result.open_graph with
    | Some id when Edit_graph.find (network value').graph.geometry ~node_id:id <> None ->
        Selection.select id selection
    | Some _ | None -> selection in
  (* Space e selects the scene's World, then enters it *)
  let selection = match target with
    | Some (Document.Inside id) when List.mem Leader.Go_world actions && level = Document.Scene ->
        Selection.select id selection
    | _ -> selection in
  let value' = { value' with selection; menu = result.menu; tree = result.tree; probes;
    (* a node added from the menu is the selection *)
    scope_view = (match !added with
      | [] ->
          (* a row chosen in the list of a geometry object selects the node that made it in the
             graph pane, whose inspector edits the text *)
          (match List.find_map (function Pxui_shell.Tree.Select [ id ] -> Some id | _ -> None)
                   result.tree_intents with
           | Some id when (match value.level with
               | Document.Inside oid -> kind value oid = Some "geometry" | Scene -> false) ->
               (match node_path value id with
                | Some path -> Pxui_graph.Scope.select [ path ] result.scope_view
                | None -> result.scope_view)
           | _ -> result.scope_view)
      | paths -> Pxui_graph.Scope.select paths result.scope_view) } in
  let value' = match target with
    | Some level when level <> value'.level -> open_level (remember value') level
    | Some level -> open_level value' level
    | None -> value' in
  (* u goes back along the route taken *)
  let value' = match value'.back with
    | (back_level, pane_graph) :: rest when List.mem Leader.Up actions && target = None && followed = None ->
        let back_level = Document.resolve_level doc back_level in
        { (open_level { value' with back = rest } back_level) with pane_graph }
    | _ -> value' in
  let value' = match followed with Some graph -> go value' graph | None -> value' in
  (* In the World, Space m flips the view pane to the lat-long map. *)
  let map_view = if List.mem Leader.Toggle_map actions && in_world value'
    then not value'.map_view else value'.map_view && in_world value' in
  let value' = { value' with map_view } in
  (* a renamed graph keeps being the one shown, and the one [u] returns to *)
  let value' = match !renamed with
    | Some (old, now) ->
        let name = Option.map (fun g -> if g = old then now else g) in
        { value' with pane_graph = name value'.pane_graph;
          back = List.map (fun (level, g) -> level, name g) value'.back }
    | None -> value' in
  (* a row of the Navigator opens its graph in the graph panel, selecting a node there *)
  let outlined = List.find_map (function
    | Navigator.Open { graph; node } -> Some (graph, node)
    | _ -> None) result.outline_intents in
  (* Space j, or a material just made, shows its graph like a row of the outline *)
  let outlined = match outlined, result.prompt_intent, !created with
    | None, Some (Go graph), _ | None, _, Some graph -> Some (graph, None)
    | _ -> outlined in
  let value' = { value' with outline = result.outline;
    select_later = (match outlined with Some (_, Some node) -> [ node ] | _ -> value'.select_later);
    text = if List.exists (function Navigator.Macro _ -> true | _ -> false) result.outline_intents
      then { value'.text with Text_pane.tab = Text_pane.Document } else value'.text } in
  (* a node of the graph already shown is selected now; of another graph, once the pane shows it *)
  let value' = match outlined with
    | Some (graph, Some node) when graph_name value' = Some graph
        && (match value'.scope_key with Some k -> k.graph = graph | None -> false) ->
        { value' with select_later = [];
          scope_view = fst (Pxui_graph.Scope.run_command (Pxui_graph.Scope.select [ node ] value'.scope_view)
            Pxui_graph.Scope.Frame_selection) }
    | _ -> value' in
  let value' = match outlined with Some (graph, _) -> go value' graph | None -> value' in
  (* the graph panel's own projection: list and text views are panels of their own now (Space l
     retypes), so opening a graph is the only thing that changes it *)
  let projections = if result.open_graph <> None || outlined <> None then
      Level_map.add value'.level Graph_view value'.projections
    else match !view_pick with
    | Some view when view <> Text_view || graph_name value' <> None -> Level_map.add value'.level view value'.projections
    | Some _ -> value'.projections
    | None -> match List.find_map (function
        | Leader.Panel_retype (Pxui_shell.Layout.Graph | List | Lisp as p) when value'.focus = Graph -> Some p
        | _ -> None) actions with
      | Some Pxui_shell.Layout.Graph -> Level_map.add value'.level Graph_view value'.projections
      | Some List -> Level_map.add value'.level List_view value'.projections
      | Some _ when graph_name value' <> None -> Level_map.add value'.level Text_view value'.projections
      | _ -> value'.projections in
  let value' = { value' with projections; text;
    rows = !row_sets;
    live_cook = result.live_cook } in
  let value' = apply_text { value' with timeline; history; locals = result.locals } result.text_intents in
  (* each other text pane's intents fold into its own state *)
  let value' = List.fold_left (fun v (key, _, intents) -> apply_text_at v key intents)
    value' result.other_texts |> sync_scope in
  let doc = value'.doc in
  let frame_request = match result.frame_request, value'.level with
    | Some node, Inside id when kind value' id = Some "geometry" -> Some (id, node)
    | _ -> None in
  if doc.workspace != value.doc.workspace then
    Cook.set_volatile value.cook (Flow_sop.Lower.is_volatile (snd doc.workspace));
  let probes = match value'.scope_key with Some k when scope_name value' <> None -> k.targets | _ -> [] in
  let lit, lit_cache = lit_tags value' in
  let cooked = Cook.update ~live:result.live_cook ~probes ~lit
      value.cook ~settings:doc.settings
      ~objects:(geometry_objects value')
      ~edit_error:result.edit_error ~effects
      ~timeline_changes ~timeline ~frame ~frame_request in
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
        let view = match active_view value' (geometry value' result.workspace frame) with
          | Some { panel = View key; _ } when Option.fold ~none:false
              ~some:(fun shell -> List.mem_assoc key shell.Document.views) doc.shell -> `Only key
          | _ -> `Primary in
        Some (List.fold_left (fun union (piece : _ Cook.piece) ->
          if not (view_wants value' view piece.id) then union else
          match piece.bounds, union with
          | None, union -> union
          | Some bounds, None -> Some (world_bounds piece.id bounds)
          | Some bounds, Some (lo, hi) ->
              let a, b = world_bounds piece.id bounds in
              Some (lower lo a, upper hi b)) None cooked.cook.pieces)
    | framed, _ -> framed in
  let document_changed = doc != value.doc in
  (* [y]: the payload is held by the handle (no pointer capture); a press or Enter puts it *)
  let carry, pick_error = match value.carry with
    | Some c -> Some { c with report = carry_report }, None
    | None when List.mem Leader.Pick_up actions ->
        (match carry_payload value' with
         | Ok payload ->
             Pxui.Ui.carry value'.ui ~kind:payload.kind ~value:payload.value ();
             Some { payload; via = `Keys; original = value'.doc; settled = value'.cook.Cook.pieces;
                    report = None; targets = None;
                    chosen = None; anchor = Some frame.mouse; preview = None; resting = None; hint = None }, None
         | Error message -> None, Some message)
    | None -> None, None in
  (* a cook that gave back every piece it had (the text changed, the objects did not) leaves
     nothing to recompose, and no accumulating render to restart *)
  let prepared_changed = cooked.prepared_changed
    && not (List.equal ( == ) (Cook.pieces cooked.cook) (Cook.pieces value.cook)) in
  let new_notice = if guide_error <> None then guide_error
    else if pick_error <> None then Option.map (fun m -> Refusal, m) pick_error
    else if copied <> None then copied
    else if document_changed && Option.is_none loaded && not undone then Option.map (fun m -> Info, m) !edit_note
    else notice in
  { core = { value' with timeline; cook = cooked.cook; lit = lit_cache; edit_error = cooked.edit_error;
      status_fps; status_fps_at; last_dt = frame.dt; steady; guide; hud; focus = result.focus; focus_path = result.focus_path;
      pane_keys = result.pane_keys; graph_panes = result.graph_panes; leader; held_keys;
      prompt;
      queued = (match result.prompt_intent with Some (Run_action action) -> [action]
        | _ when all_ui_visible && List.mem Leader.Add_node actions && not graph_shown
            && has_panel value' Pxui_shell.Layout.Graph -> [Leader.Add_node]
        | _ -> []);
      carry;
      notice = new_notice;
      notice_at = if new_notice <> value'.notice then frame.time else value'.notice_at };
    effects; prepared_changed;
    scene_changed = carry_changed || doc.scene != value.doc.scene || prepared_changed;
    framed;
    loaded_view = Option.map (fun (preset : Preset.loaded) -> preset.view) loaded;
    actions = (if Option.is_some entered_camera && entered_camera = doc.active_camera
      then actions @ [Leader.Look_through_camera] else actions); panel = result.panel;
    input }

(* One frame of the editor.  A carry takes its turn first (its keys, the ends of the gesture, the
   preview document the panels then read) and the frame the rest of the editor sees has the keys
   it took removed. *)
let update value ~all_ui_visible ~text_focus ~camera_panel ~view_handles ~render_status
    ~error_status ~view_state (frame : Frame.t) =
  let value, frame, carry_changed = carry_step value ~text_focus frame in
  update_frame ~carry_changed value ~all_ui_visible ~text_focus ~camera_panel ~view_handles
    ~render_status ~error_status ~view_state frame

(* Environment-owned scene edits (camera bookkeeping, a camera following the viewport): view
   state, never an undo entry.  [`Reset] starts the history, [`Amend] folds into the present
   entry and keeps what redo would restore. *)
let scene_edit value mode ?(active_camera = value.doc.active_camera) scene =
  if value.carry <> None then value else
  let edited = { value.doc with scene = { value.doc.scene with graph = Result.get_ok (Flow_sop.Network.with_geometry scene value.doc.scene.graph);
      displayed = Document.displayed_of ?previous:value.doc.scene.displayed (Flow_sop.Network.of_geometry scene) None };
    active_camera } in
  (* a camera that follows the viewport is an edit of the text when the text declares it *)
  match Doc.reconcile ~factories:value.factories ~adopt:false value.doc edited with
  | Error message -> { value with edit_error = Some message }
  | Ok doc ->
  let history = match mode with
    | `Reset -> Editor_core.History.create doc
    | `Amend -> commit ~merge:Repair doc value.history in
  (* camera bookkeeping is not unsaved work: a document that was the file's still is *)
  { value with doc; history; filed = if same_text value.doc value.filed then doc else value.filed }

let machinery ?under value ~all_ui_visible =
  if all_ui_visible || value.leader <> Leader.Idle then Pxui.Ui.scene ?under value.ui
  else []

let close value =
  Pxui.Ui.destroy value.ui;
  Cook.close value.cook

(* A sketch-driven settings change: one undo step and a fresh cook, since
   [prepare] reads the settings. *)
let set_settings value settings =
  if settings == value.doc.settings || value.carry <> None then value else
  match Doc.reconcile ~factories:value.factories value.doc { value.doc with settings } with
  | Error message -> { value with edit_error = Some message }
  | Ok doc ->
      { value with doc; cook = Cook.force value.cook;
        history = commit ~label:"Settings" doc value.history }

(* An edit of the render settings (the root): written to the root's call, or the first edit writes
   a root over the scene's result; one undo step, merged while scrubbed. *)
let set_root value root =
  if root = value.doc.root || value.carry <> None then value else
  match Doc.reconcile ~factories:value.factories value.doc { value.doc with root } with
  | Error message -> { value with edit_error = Some message }
  | Ok doc ->
      { value with doc;
        history = commit ~label:"Render settings" ~merge:(Gesture "render settings") doc value.history }

(* A host-driven gesture on a workspace document ([Editor3.edit], W11's
   entry): the same reduction as a [Syntax_edit] intent, committed as one
   history entry named by the op ([Gesture] merge for a scrub). *)
let syntax_edit value op =
  Result.map (fun doc -> install value doc ~label:(Flow_sop.Flow_edit.label op)
    ~merge:(Option.fold ~none:Editor_core.History.Step
      ~some:(fun key -> Editor_core.History.Gesture key) (Flow_sop.Flow_edit.gesture op)))
    (Doc.syntax_edit_result ~factories:value.factories value.doc op)
  |> Result.map_error Flow.Diagnostic.to_string

(* The scene's World at timeline [time] (the day cycle advances with it). *)
let world ?(view = `Primary) value ~time =
  let own = match view with
    | `Only key -> List.assoc_opt key value.doc.Document.view_worlds
    | _ -> None in
  match own with
  | Some None -> None
  | Some (Some (w : Document.view_world)) -> Layers.to_world ~time w.node w.layers
  | None ->
  match List.filter (view_wants value `Primary) (Objects.ids "world" (scene value)) with
  | id :: _ when Edit_graph.is_bypassed (scene value) ~node_id:id -> None
  | id :: _ ->
      Option.bind (Edit_graph.find (scene value) ~node_id:id) (fun node ->
        Option.bind (Document.Int_map.find_opt id value.doc.Document.networks)
          (fun network -> Layers.to_world ~time node network))
  | [] -> None

(* Visible objects' world transforms with their latest cook.  Objects that only a viewport
   over another scene instance draws ([Document.shell]'s views) are left out unless asked
   for: [`All], or [`Only key] for that viewport. *)
(* Lights and cameras follow the same instance membership as the geometry. *)
let scene_for_view ?scene:override ?(view = `Primary) value =
  let scene = Option.value override ~default:(scene value) in
  let unwanted = List.filter_map (fun (i : Edit_graph.node_info) ->
    if view_wants value view i.id then None else Some i.id) (Edit_graph.inspect scene) in
  if unwanted = [] then scene else Edit_graph.remove_nodes unwanted scene

let placed_pieces ?(render = false) ?(view = `Primary) value =
  List.filter_map (fun (piece : _ Cook.piece) ->
    match Edit_graph.find (scene value) ~node_id:piece.id with
    | Some node when view_wants value view piece.id && Objects.visible node
        && not (Edit_graph.is_bypassed (scene value) ~node_id:piece.id)
        && (not render || Objects.flag "render" node) ->
        Some (Objects.world (scene value) piece.id, piece)
    | Some _ | None -> None) (pieces value)

(* How a viewport over another scene instance renders: that instance's [scene/root] (its settings and
   its camera), else the document's *)
let view_root_opt value key = List.assoc_opt key value.doc.Document.view_roots

let view_root value key =
  Option.fold ~none:value.doc.Document.root ~some:(fun (r : Document.view_root) -> r.params)
    (view_root_opt value key)

let world_id value = match Objects.ids "world" (scene value) with
  | id :: _ -> Some id | [] -> None

(* A parameter edit made in the view (a map drag, a World rotation): one
   undo entry per pointer gesture. *)
let edit_node value level node_id values ~label =
  if value.carry <> None then value else
  match Document.network value.doc level with
  | None -> value
  | Some network ->
      match Edit_graph.apply_parameters network.graph.geometry ~node_id values with
      | Error _ -> value
      | Ok (graph, _) ->
          let edited = Document.with_network value.doc level { network with graph = Result.get_ok (Flow_sop.Network.with_geometry graph network.graph) } in
          (match Doc.reconcile ~factories:value.factories value.doc edited with
           | Error message -> { value with edit_error = Some message }
           | Ok doc ->
               Cook.set_volatile value.cook (Flow_sop.Lower.is_volatile (snd doc.workspace));
               { value with doc;
                 history = commit ~label ~merge:(Gesture
                   (parameter_gesture label level node_id values)) doc value.history })

(* A click in the view (plan W6): the primitive under the ray, its
   [__flow_src] tag, the merge input that made it (`Lower.provenance`), then
   the selection is that node and every enclosing zone probes that iteration,
   so the highlight ({!lit_tags}), the selectors and the inspector agree.  A
   click on nothing deselects.  A merge of merges keeps the innermost tag, so
   the origin is exact through nested collecting merges.  Geometry drawn as
   instances is picked per instance ({!Cook.pick}), and hits compare by the
   ray parameter, so any scale is exact. *)
(* The graph of a [shop_materialpath]: the material graph of that name, else the one whose
   [:name] it is. *)
let material_graph value path =
  let ws, _ = value.doc.Document.workspace in
  let materials = List.filter_map (fun (g : Flow.Workspace.graph) ->
    if g.context = Flow.Workspace.Material then Some g.name else None) ws.checked.graphs in
  if List.mem path materials then Some path
  else match value.scope_key with
    | Some { evaluated = Some ev; _ } ->
        List.find_map (fun (graph, v) -> match v with
          | Flow.Eval.Struct ("material/standard", fields)
            when List.mem graph materials && List.assoc_opt "name" fields = Some (Flow.Eval.Text path) -> Some graph
          | _ -> None) ev.results
    | _ -> None

let pick ?view ?(alt = false) value ~origin ~direction =
  (* the focused viewport's own scene instance, when it has objects of its own *)
  let view = match view, value.doc.Document.shell with
    | Some key, Some shell when List.mem_assoc key shell.views -> `Only key
    | _ -> `Primary in
  let nearest_by pick = List.fold_left (fun best (matrix, piece) ->
    match Mat4.inverse matrix with
    | None -> best
    | Some inverse ->
        match pick piece ~origin:(Mat4.transform_point inverse origin)
            ~direction:(Mat4.transform_direction inverse direction), best with
        | Some (distance, _), Some (nearer, _) when distance >= nearer -> best
        | Some hit, _ -> Some hit
        | None, _ -> best) None (placed_pieces ~view value) in
  match value.doc.Document.workspace, value.scope_key with
  | _ when alt ->
      (* Alt-click: the material on that primitive *)
      (match nearest_by Cook.pick_material with
       | Some (_, Some path) ->
           (match material_graph value path with
            | Some graph -> go value graph
            | None -> { value with notice = Some (Refusal, "No material graph for " ^ path) })
       | _ -> value)
  | (ws, lowered), Some { scope; _ } when scope_name value <> None ->
      let nearest = nearest_by Cook.pick in
      let hit = Option.bind nearest (fun (_, tag) ->
        Flow_sop.Lower.origin lowered tag) in
      (match hit with
       | Some o ->
           (* geometry of another graph (a viewport over another scene instance draws its own
              objects): the pane shows that graph, the node is selected there once it does *)
           let root = List.hd o.site in
           let value, scope = if root = (match value.scope_key with Some k -> k.graph | None -> root)
             then value, scope
             else match Lazy.force value.flow_catalog with
               | Some catalog -> { value with pane_graph = Some root },
                   Flow_sop.Projection.of_graph catalog ws.checked root
               | None -> value, scope in
           (match Hashtbl.find_opt (Flow_sop.Probe.chains scope) o.site with
            | Some chain ->
                (* the outermost collapsed loop stands for what is inside it *)
                let collapsed zone = Layout_by_path.Path_map.find_opt zone ws.layout.collapsed = Some true in
                let shown = match List.find_opt collapsed chain with Some zone -> zone | None -> o.site in
                let probes = List.fold_left2 (fun probes zone index ->
                  Layout_by_path.Path_map.add zone index probes) value.probes chain
                  (if List.compare_lengths chain o.iter = 0 then o.iter
                   else List.map (fun _ -> 0) chain) in
                let in_pane = root = (match value.scope_key with Some k -> k.graph | None -> root) in
                { value with probes;
                  select_later = (if in_pane then [] else [ shown ]);
                  scope_view = if in_pane then Pxui_graph.Scope.select [ shown ] value.scope_view
                    else value.scope_view }
            | None -> value)
       | None -> { value with scope_view = Pxui_graph.Scope.clear_selection value.scope_view })
  | _ -> value

(* A changed source file (plan W11): the whole text replaces the document as one
   history entry; layout, settings, probes and the selection (all keyed by path)
   stay.  A refused text changes nothing but the pane: it shows the file's text
   with the diagnostics, and the status says the last good document is kept. *)
let reload value ~name text =
  Result.map (fun value ->
    let clean (text : Text_pane.state) =
      { text with draft = None; doc_base = None; binding_base = None; graph_base = None; doc_errors = []; binding_draft = None; binding_errors = [];
        graph_draft = None; graph_errors = [] } in
    { value with notice = Some (Info, "Reloaded " ^ name); text = clean value.text; filed = value.doc;
      locals = List.map (fun (key, l) -> key, { l with code = clean l.code }) value.locals })
    (text_edit ~label:("Reload " ^ name) value text)

let reload_failed value ~name text diagnostics =
  let first = match diagnostics with
    | [] -> ""
    | d :: _ -> (match Text_pane.line_of text d with
        | Some line -> Printf.sprintf ": line %d, %s" line d.Flow.Diagnostic.message
        | None -> ": " ^ d.Flow.Diagnostic.message) in
  { value with notice = Some (Refusal, Printf.sprintf "%s not reloaded%s" name first);
    text = { value.text with tab = Text_pane.Document; draft = Some text; doc_base = Some (fst value.doc.workspace); doc_errors = diagnostics } }

(* The carry's hovered viewport has been looked at by the host: the surface under the pointer
   (the object it belongs to and the material graph its primitive reads) is where a material goes,
   and the scene where a SOP graph does.  [view] is the viewport's own scene instance. *)
let carry_over_surface ?view value ~origin ~direction =
  match value.carry with
  | Some ({ report = Some { over = Carry.Viewport _; dropped }; payload = { kind = ("material" | "sop"); _ }; _ } as c) ->
      let view = match view, value.doc.Document.shell with
        | Some key, Some shell when List.mem_assoc key shell.views -> `Only key
        | _ -> `Primary in
      let nearest = List.fold_left (fun best (matrix, (piece : _ Cook.piece)) ->
        match Mat4.inverse matrix with
        | None -> best
        | Some inverse ->
            match Cook.pick_material piece ~origin:(Mat4.transform_point inverse origin)
                ~direction:(Mat4.transform_direction inverse direction), best with
            | Some (distance, _), Some (nearer, _, _) when distance >= nearer -> best
            | Some (distance, path), _ -> Some (distance, piece.id, path)
            | None, _ -> best) None (placed_pieces ~view { value with cook = { value.cook with Cook.pieces = c.settled } }) in
      let place = match nearest with
        | Some (_, object_, path) ->
            Carry.Surface { object_; material = Option.bind path (material_graph value) }
        | None ->
            (* nothing under the pointer: a SOP graph goes to the scene, a material has no place *)
            (match List.find_map (fun (g : Flow.Workspace.graph) ->
               if g.context = Flow.Workspace.Scene then Some g.name else None)
               (fst value.doc.Document.workspace).checked.graphs with
             | Some graph when c.payload.kind = "sop" -> Carry.Graph graph
             | _ -> Carry.Viewport "") in
      { value with carry = Some { c with report = Some { over = place; dropped } } }
  | _ -> value

(* A pointer carry is over a viewport: the host should look through the viewport's camera. *)
let carry_viewport value = match value.carry with
  | Some { report = Some { over = Carry.Viewport key; _ }; payload = { kind = ("material" | "sop"); _ }; _ } -> Some key
  | _ -> None

let carrying value = value.carry <> None
