(** Reusable graph-driven procedural sketch environments.

    Both environments share a responsive view/graph/inspector workspace,
    persistent graph navigation, generated node inspection, bounded
    asynchronous cooking, status UI, and finite native execution. Their thin
    adapters own only the dimensional camera, viewport composition, and
    still-image renderer. Overlay callbacks receive a frame and coordinates
    local to the current view pane. *)

(** The v4 document a sketch can open the editor on: a checked workspace, its
    layout by path and its settings (see [Editor_document.Workspace_doc]). *)
module Workspace_doc = Editor_document.Workspace_doc

val workspace_catalog : ?factories:Procedural.Edit_graph.factory list -> unit ->
  (Flow.Check.catalog, Flow.Diagnostic.t) result
(** The catalog a workspace text is checked against ({!Workspace_doc.of_text}):
    the SOP factories (default [Sop_catalog.Editor.factories]) plus the scene,
    world and settings kinds generated from the editor's schemas. *)

type window = Editor_document.Contexts.window =
  { title : string; width : int; height : int; fps : int; seed : int }

val workspace_window : Workspace_doc.t -> (window, Flow.Diagnostic.t) result
(** The window a workspace's settings graph asks for (defaults without one). *)

(** Sketch-owned settings in the editor document. *)
(** The [.plisp] file a running sketch came from: polled for edits, saved over. *)
module Source : sig
  type t
  val at : file:string -> digest:string -> t
  (** The file, whose text has SHA-256 [digest]. *)

  val find : path:string -> digest:string -> t option
  (** [path] under the first [dune-project] not inside [_build], walking up from the
      executable and then the working directory; [None] when there is no such file. *)

  val file : t -> string
  val poll : now:float -> t -> t * string option
  (** At most one [stat] per half second of [now]; the text when the file changed and
      differs from what the document has. *)

  val save : t -> string -> (t, [ `Changed | `Failed of string ]) result
  (** Atomically replace the file with the text, only while its digest is still the
      remembered one ([`Changed] otherwise); the write does not reload. *)
end

module Settings : sig
  type t
  val none : t
  val make : 'record Editor_core.Param.schema -> 'record -> t
  (** Settings drawn in the inspector while no node is selected. *)

  val get : 'record Editor_core.Param.schema -> t -> 'record
  (** Read the current record back; raises [Invalid_argument] when [schema]
      does not describe it. *)
end

type layout = Pxui_shell.Layout.t

(** The shell of a document without an editor graph: view 45%, graph 35%, inspector 20%.
    A workspace with a [(graph editor ...)] brings its own. *)
val default_layout : layout

(** Editor internals exposed for tests and diagnostics.
    Layout and chrome live in [Pxui_shell]; sketches use [Editor3]/[2]. *)
module Private : sig
  (** Unstable test and diagnostic hooks. These are outside the supported
      sketch API and may change without compatibility shims. *)
  (** Helix-style leader keys. Space (while no text field is focused) opens a
      centered which-key panel; the next key runs a binding from the global
      scope or from the focused pane, the one last clicked. Escape, Space, an
      unknown key, a click, or window focus loss cancel it. *)
  module Leader : sig
    type action =
      | Save_preset | Browse_presets | Save_source
      | Toggle_timeline | Toggle_graph | Toggle_inspector | Hide_ui | Open_camera
      | Play_pause | Reset | Stop
      | Add_node | Frame_tile | Frame_camera
      | Look_through | Fly | Tool of int
      | Undo | Redo
      | Panel_split of Pxui_shell.Layout.axis | Panel_close | Panel_retype of Pxui_shell.Layout.panel
      | Toggle_projection | Restore_layout | Enter | Up | Go_world
      | World_emit | World_reseed | World_time of float | World_play | World_preset of int
      | Scope_command of Pxui_graph.Scope.command
      | List_command of Pxui_shell.Tree.command
      | Guide_toggle | Guide_keys
      | Command_palette
      | Sketch_command of string

    type command = (Pxui_shell.Layout.panel, action) Editor_core.Command.t

    type state = Editor_core.Router.state = Idle | Pending of string

    val scope : Pxui_shell.Layout.panel -> Pxui_shell.Layout.panel
    (** The scope a focused panel's commands use: every viewport is [View ""], the list and
        lisp panels are the graph pane's. *)

    val keymap : command list
    (** The single table behind dispatch, which-key, and the palette. *)

    val keymap3 : command list
    (** [keymap] plus the 3D view commands ([w] fly, [v] look through). *)

  end

  (** [timeline_frames] (default 240) is the scrub range of the timeline bar,
      extended while playback runs past it. [name] (default ["sketch"]; [run]
      uses the window title) is recorded in presets, which live in [presets]
      (default [~/.prismel/<name>]): [Space s] saves the full document under a
      typed name (prefilled with the time), [Space b] searches, loads (Enter, one
      undo entry), and deletes (Delete twice) them. See {!Preset}. *)

  (** Effect- and dependency-aware cook scheduler. It fires initially, after a
      committed cook parameter change, after [force], and whenever the sketch
      clock changed and any reachable node declares [Time] or [Frame]. While a
      primary-pointer edit is held it cooks only when [live] (the inspector's
      "Live update while dragging", on by default) and the worker is idle;
      otherwise only the latest desired cook is retained until release. *)
  module Document : sig
    type t
    val scene_graph : t -> Procedural.Edit_graph.t
    val object_network : t -> int -> (Flow_sop.Network.t * int option) option
    (** An object's immutable network and optional geometry display node.
        A missing owner returns [None]; an empty geometry network has no display. *)
  end

  (** Presets: the workspace as an s-expression file (source, layout,
      settings) plus the environment view. Only workspace documents save. *)
  module Preset : sig
    type loaded = { doc : Document.t; view : Yojson.Safe.t }
    val sanitize : string -> string
    val default_name : unit -> string
    val path : directory:string -> name:string -> string
    val save : directory:string -> name:string -> doc:Document.t ->
      view:Yojson.Safe.t -> (string, string) result
    val list : directory:string -> (string * float) list
    val delete : directory:string -> name:string -> (unit, string) result
    val load : path:string -> factories:Procedural.Edit_graph.factory list ->
      settings:Settings.t -> (loaded, string) result
  end

  module Schedule : sig
    type t
    val initial : t
    val step :
      ?live:bool -> t -> graphs:Procedural.Graph.t list -> effects:Procedural.Parameter.effects ->
      context_changed:bool -> force:bool -> busy:bool -> frame:Prismel.Frame.t ->
      t * bool
  end

  (** Host cook boundary, exposed for deterministic worker tests and measurements. *)
  module Pick : sig
    module Set : Set.S with type elt = int
    val tags : Pdk.Geometry.t -> int array option
    (** The [__flow_src] tag of every primitive, when the geometry has them. *)
    val tint : Procedural.Session.output -> Set.t -> Procedural.Session.output
    (** The primitives whose tag is in the set take the selection tint, the
        rest are dimmed (a vertex [Cd]); the empty set changes nothing. *)
  end

  (** The workspace text pane's pure part: the text each tab shows. *)
  module Text_pane : sig
    type tab = Selection | Graph | Document
    type shown = {
      text : string;
      mark : (int * int) option;
      binding : (string list * string) option;
      applied : string Lazy.t;
    }
    val make_shown : Flow.Syntax.t list -> string -> string list option -> tab -> shown
    val line_of : string -> Flow.Diagnostic.t -> int option
  end

  module Cook : sig
    type bounds = Prismel.Vec3.t * Prismel.Vec3.t
    type 'prepared piece = {
      id : int;
      graph : Procedural.Graph.t;
      prepared : 'prepared;
      bounds : bounds option;
      settings : Settings.t;
      context : string;
      output : Procedural.Session.output;
      lit : Pick.Set.t;
      surface : Pdk.Surface_index.t option Lazy.t;
    }
    type 'prepared t
    type 'prepared update = {
      cook : 'prepared t;
      edit_error : string option;
      prepared_changed : bool;
      framed : bounds option option;
    }
    val create : prepare:(Settings.t -> Procedural.Session.output -> ('a, string) result) ->
      seed:int64 -> grain:int -> ?domains:int -> ?await:bool -> max_entries:int ->
      max_payload_bytes:int -> unit -> ('a t, string) result
    (** [await] (default: [PRISMEL_MAX_FRAMES] is set) makes [update] block on
        the cook it submits, so a fixed-step run shows exactly frame n. *)
    val status : 'a t -> Procedural.Async_cook.status
    val set_volatile : 'a t -> (int -> bool) -> unit
    (** Pass [Flow_sop.Lower.is_volatile lowered] after each lowering (W3). *)
    val stats : 'a t -> Procedural.Session.stats
    val seconds : 'a t -> float option
    (** The last completed cook, in seconds. *)
    val pieces : 'a t -> 'a piece list
    val applied : 'a t -> int -> Flow_sop.Value_lane.resolved option
    val force : 'a t -> 'a t
    val geometry : 'a t -> object_id:int -> node_id:int -> Flow_sop.Probe.geometry option
    (** The counts of a compiled node an object's last [~probes] asked for. *)
    val pick : 'a piece -> origin:Prismel.Vec3.t -> direction:Prismel.Vec3.t ->
      (float * int) option
    (** The nearest displayed primitive under a ray in the piece's own space:
        its distance and provenance tag. *)
    val update : ?live:bool -> ?probes:(int * int) list -> ?lit:Pick.Set.t ->
      'a t -> settings:Settings.t ->
      objects:(int * Flow_sop.Network.t * int) list -> edit_error:string option ->
      effects:Procedural.Parameter.effects -> timeline_changes:Sketch_support.Timeline.change list ->
      timeline:Sketch_support.Timeline.t -> frame:Prismel.Frame.t ->
      frame_request:(int * int) option -> 'a update
    val close : 'a t -> unit
  end
end

(** The renderer choice a sketch offers in its settings block: one shared
    field, so the control reads the same in every sketch. The sketch's
    [prepare] reads it back through its own schema. *)
module Renderer : sig
  type t = Path_traced | Raster | Wireframe

  val field :
    default:t -> get:('record -> t) -> set:(t -> 'record -> 'record) ->
    'record Editor_core.Param.field
  (** The ["renderer"] field labelled "Renderer". *)

  val of_env : string -> t option
  (** ["path"], ["raster"], or ["wireframe"] from an environment variable. *)

  val wire_mesh : Pdk.Geometry.t -> (Prismel.Mesh.t, string) result
  (** Every polygon edge once, as a line mesh for the wireframe renderer. *)

  val wire_color : Prismel.Color.t -> Prismel.Color.t
  (** A contrasting blue wire color for a light or dark viewport background. *)
end

module Editor3 : sig
  type 'prepared t
  type nonrec layout = layout
  val default_layout : layout

  val create :
    ?layout:layout ->
    ?name:string ->
    ?presets:string ->
    ?timeline_frames:int ->
    ?factories:Procedural.Edit_graph.factory list ->
    ?settings:Settings.t ->
    ?commands:(Pxui_shell.Layout.panel, 'prepared t -> 'prepared t) Editor_core.Command.t list ->
    ?lights:Prismel.Light.t list ->
    ?world:Prismel.World.t ->
    ?camera:Prismel.Easy_camera.t ->
    ?lens:Prismel.Camera.lens ->
    ?background:Prismel.Color.t ->
    ?seed:int64 ->
    ?grain:int ->
    ?domains:int ->
    ?max_entries:int ->
    ?max_payload_bytes:int ->
    workspace:Workspace_doc.t ->
    ?source:Source.t ->
    prepare:(Settings.t -> Procedural.Session.output -> ('prepared, string) result) ->
    scene3:(Procedural.Graph.t -> 'prepared -> Prismel.Scene3.t) ->
    ?overlay:(Procedural.Graph.t -> 'prepared option -> Prismel.Frame.t ->
      Prismel.Scene.t) ->
    ?status:('prepared option -> string option) ->
    unit ->
    ('prepared t, string) result
  (** [lens] is the default camera object's depth of field (pinhole
      otherwise). [prepare] runs on the cook worker domain with submission settings.
      It must only do pure CPU work on immutable/disjointly owned data;
      SDL, Metal, textures, fonts, audio, UI and runtime caches stay on the
      initial domain. [scene3] and [overlay] run on the initial domain. *)

  val update : 'prepared t -> Prismel.Frame.t -> 'prepared t

  val update_with :
    'prepared t -> Prismel.Frame.t -> inspector:(Pxui.Ui.t -> 'a) ->
    'prepared t * 'a option
  (** [update], also building sketch-owned kit widgets below the camera and
      render sections shown while no node is selected. The result is [None]
      on frames where that panel is not built. *)

  (* Call from [Sketch.run_state ~after_present] when driving the environment
      manually so PNG requests save the completed frame. *)
  val after_present : 'prepared t -> Prismel.Frame.t -> 'prepared t

  val settings : 'prepared t -> Settings.t
  val set_settings : 'prepared t -> Settings.t -> 'prepared t
  (** Replace the sketch settings from code: one undo step and a fresh cook,
      since [prepare] receives them. Inspector edits do the same. *)

  (* [?status] text joins the status bar under the view (cook state, then
     the sketch's line, e.g. renderer stats); keep view overlays for pictures. *)
  (* [?commands] (on [create]/[run]) add sketch [Editor_core.Command]s to the
     same table as the built-ins: triggers join key routing and which-key, and
     scoped commands appear while their pane has focus. A command's [action]
     gets this environment after the frame. [create] rejects reserved IDs,
     overlapping triggers and leader prefixes, and aliases with different
     action closures. Bind each alias to the same action value. Chord keys
     and leader sequences are case-insensitive; modifier lists are normalized. *)

  (** The workspace keeps one [Editor_core.History] history of the editable document:
      graph edits and inspector commits are entries, continuous slider drags
      collapse into one, and Command/Ctrl-Z, Shift-Command/Ctrl-Z, and
      Ctrl-Y step it. *)
  val can_undo : 'prepared t -> bool
  val can_redo : 'prepared t -> bool
  val undo_label : 'prepared t -> string option
  (** The label of the edit undo would revert ("Repeat", "Connect", ...). *)

  val redo_label : 'prepared t -> string option

  val workspace : 'prepared t -> Workspace_doc.t
  (** The document the editor is open on: every document is a workspace. *)

  val probe : 'prepared t -> Flow.Workspace.path -> int option
  (** The iteration the zone at that path shows (view state, kept by path across
      edits and reloads, never in history). *)

  val set_probe : 'prepared t -> Flow.Workspace.path -> int -> 'prepared t

  val node_box : 'prepared t -> Flow.Workspace.path -> (int * int * int * int) option
  (** The rectangle, in window points, of the node at a path in the graph pane as last laid out
      (tests and tools that click on a node). *)

  val edit : 'prepared t -> Flow_sop.Flow_edit.op -> ('prepared t, string) result
  (** One gesture on the workspace: rewrite the source, re-check, lower into
      the scene's objects, recook, and record one history entry named by the
      op. An error changes nothing. *)
  val scene : 'prepared t -> Prismel.Frame.t -> Prismel.Scene.t
  val close : 'prepared t -> unit
  val crash_dump : 'prepared t -> string -> unit
  (** Write the document (a preset) and editor state into a crash report
      folder; pass it as [Sketch.run_state ~crash_dump] when driving the
      editor from your own [run_state]. [run] does this itself. *)
  val graph : 'prepared t -> Procedural.Graph.t
  val document : 'prepared t -> Procedural.Edit_graph.t
  val selected_node : 'prepared t -> Procedural.Node.t option
  val displayed_node : 'prepared t -> Procedural.Node.t
  val prepared : 'prepared t -> 'prepared option
  val camera : 'prepared t -> Prismel.Easy_camera.t
  (** The interactive viewport camera. *)

  val render_camera : 'prepared t -> Prismel.Camera.t
  (** The ACTIVE camera object's view and lens (the viewport camera when the
      document has none). A default camera following the viewport is added
      to a document without one, and again if the last is deleted (inside
      the same undo entry). With follow viewport on, viewport motion writes
      the node (one undo entry per gesture) and node edits or undo move the
      viewport. PNG export and look-through use it. *)

  type render_settings = { width : int; height : int; max_spp : int }

  val render_settings : 'prepared t -> render_settings
  (** The ACTIVE camera object's Render folder: output resolution in pixels
      (its aspect also frames look-through) and the samples per pixel at
      which a sketch's progressive renderer stops. *)

  val film : 'prepared t -> Prismel.Frame.t -> int * int * int * int
  (** The rect inside the view pane (pane-relative) that the render fills:
      the whole pane, or the render camera's aspect fitted and centred while
      looking through it. The editor paints its own 3D view into it and
      draws the sketch [overlay] inside it, with a [Frame.t] of its size, so
      an overlay drawing a film at the origin needs nothing else. *)

  val take_export : 'prepared t -> 'prepared t * string option
  (** The output path of a "Render / save PNG" request made this frame,
      taken over by the sketch (the editor then does not capture the screen
      in [after_present]); call it after [update] and before
      [after_present]. A sketch renderer exports at [render_settings]. *)

  val set_render_status : 'prepared t -> string option -> 'prepared t
  (** Replaces the status bar's render text, e.g. an export's progress. *)

  val view_camera : 'prepared t -> Prismel.Camera.t
  (** What the view pane shows this frame, for a sketch's own renderer:
      [render_camera] while looking through it, otherwise the viewport camera
      with the ACTIVE camera's lens (focused on the orbit target unless the
      camera follows the viewport). With follow viewport off, the view orbits
      freely around the camera object, whose frustum, aim line, and eye
      marker are drawn over the sketch's overlay; clicking the eye selects
      it, and W shows a handle sliding its target along the view direction,
      its focus distance. The Viewport section pairs the look-through toggle
      with "Camera follows viewport" (the ACTIVE camera's own parameter, one
      undo entry), so a fixed camera is set up by looking through it and
      orbiting. *)

  val flying : 'prepared t -> bool
  (** [Space w] with the view focused: held W/S/A/D/Q/E fly the viewport
      camera ([Easy_camera.fly]) with the pointer captured through
      [Sketch.set_relative_mouse]. Escape or focus loss exits; Space exits and
      opens the leader. *)

  val look_through : 'prepared t -> bool
  (** The view shows [render_camera] ([Space v], or the Camera panel toggle);
      orbit input is frozen unless the active camera follows the viewport. *)

  val timeline : 'prepared t -> Sketch_support.Timeline.t
  val panes : 'prepared t -> Prismel.Frame.t -> Pxui_shell.Layout.panes

  (** {2 Scene}

      The document is a scene of objects above the SOP networks. The code
      [graph] is the geometry object [geo1]; [?lights] become light objects
      and [?world] the World. The graph pane shows the open level as a graph
      or a list ([Space l]): [i], a double-click, or activating a list row
      enters a geometry object's SOP network or the World's layer stack, and
      [u] goes back up; [Space e] opens the World (created on first use), and
      [Space a] opens the add menu of the open level (objects, SOPs, or World
      layers): hover a category for its submenu, or type to search. Object transforms place each object's cook as a
      whole, so moving one never re-cooks SOPs. [graph], [document],
      [prepared], and [displayed_node] describe the open (else the first)
      geometry object. *)

  val level : 'prepared t -> string option
  (** The object whose network is open; [None] at the scene level. *)

  val scene_document : 'prepared t -> Procedural.Edit_graph.t
  (** Objects as nodes: input 0 is the parent, parameters the transform. *)

  val objects : 'prepared t -> (Prismel.Mat4.t * 'prepared) list
  (** Visible, renderable geometry objects' latest cooks at their world
      transforms, e.g. for a sketch's own path tracer. *)

  val lights : 'prepared t -> Prismel.Light.t list
  (** Visible, renderable light objects in world space. *)

  val world : 'prepared t -> Prismel.World.baked option
  (** This frame's World bake (preview size during a gesture or playback),
      or [None] without a World. *)

  val run :
    ?layout:layout ->
    ?name:string ->
    ?presets:string ->
    ?timeline_frames:int ->
    ?factories:Procedural.Edit_graph.factory list ->
    ?settings:Settings.t ->
    ?commands:(Pxui_shell.Layout.panel, 'prepared t -> 'prepared t) Editor_core.Command.t list ->
    ?lights:Prismel.Light.t list ->
    ?world:Prismel.World.t ->
    ?camera:Prismel.Easy_camera.t ->
    ?lens:Prismel.Camera.lens ->
    ?background:Prismel.Color.t ->
    ?seed:int64 ->
    ?grain:int ->
    ?domains:int ->
    ?max_entries:int ->
    ?max_payload_bytes:int ->
    config:Prismel.Sketch.config ->
    workspace:Workspace_doc.t ->
    ?source:Source.t ->
    prepare:(Settings.t -> Procedural.Session.output -> ('prepared, string) result) ->
    scene3:(Procedural.Graph.t -> 'prepared -> Prismel.Scene3.t) ->
    ?overlay:(Procedural.Graph.t -> 'prepared option -> Prismel.Frame.t ->
      Prismel.Scene.t) ->
    ?status:('prepared option -> string option) ->
    unit ->
    unit
end

module Editor2 : sig
  type 'prepared t
  type nonrec layout = layout
  val default_layout : layout

  val create :
    ?layout:layout ->
    ?name:string ->
    ?presets:string ->
    ?timeline_frames:int ->
    ?factories:Procedural.Edit_graph.factory list ->
    ?settings:Settings.t ->
    ?commands:(Pxui_shell.Layout.panel, 'prepared t -> 'prepared t) Editor_core.Command.t list ->
    ?lights:Prismel.Light.t list ->
    ?world:Prismel.World.t ->
    ?camera:Prismel.Easy_camera2.t ->
    ?background:Prismel.Color.t ->
    ?seed:int64 ->
    ?grain:int ->
    ?domains:int ->
    ?max_entries:int ->
    ?max_payload_bytes:int ->
    workspace:Workspace_doc.t ->
    prepare:(Settings.t -> Procedural.Session.output -> ('prepared, string) result) ->
    scene2:(Procedural.Graph.t -> 'prepared -> Prismel.Scene.t) ->
    ?overlay:(Procedural.Graph.t -> 'prepared option -> Prismel.Frame.t ->
      Prismel.Scene.t) ->
    ?status:('prepared option -> string option) ->
    unit ->
    ('prepared t, string) result
  (** [prepare] runs on the cook worker domain with submission settings.
      It must only do pure CPU work on immutable/disjointly owned data;
      SDL, Metal, textures, fonts, audio, UI and runtime caches stay on the
      initial domain. [scene2] and [overlay] run on the initial domain. *)

  val update : 'prepared t -> Prismel.Frame.t -> 'prepared t
  val update_with :
    'prepared t -> Prismel.Frame.t -> inspector:(Pxui.Ui.t -> 'a) ->
    'prepared t * 'a option
  (** [update], also building sketch-owned widgets in the unselected inspector.
      The result is [None] when that panel is not built. *)

  (* Call from [Sketch.run_state ~after_present] when driving the environment
      manually so PNG requests save the completed frame. *)
  val after_present : 'prepared t -> Prismel.Frame.t -> 'prepared t
  val settings : 'prepared t -> Settings.t
  val set_settings : 'prepared t -> Settings.t -> 'prepared t
  val can_undo : 'prepared t -> bool
  val can_redo : 'prepared t -> bool
  val undo_label : 'prepared t -> string option
  (** The label of the edit undo would revert ("Repeat", "Connect", ...). *)

  val redo_label : 'prepared t -> string option

  val workspace : 'prepared t -> Workspace_doc.t
  (** The document the editor is open on: every document is a workspace. *)

  val node_box : 'prepared t -> Flow.Workspace.path -> (int * int * int * int) option
  (** The rectangle, in window points, of the node at a path in the graph pane as last laid out
      (tests and tools that click on a node). *)

  val edit : 'prepared t -> Flow_sop.Flow_edit.op -> ('prepared t, string) result
  (** One gesture on the workspace: rewrite the source, re-check, lower into
      the scene's objects, recook, and record one history entry named by the
      op. An error changes nothing. *)
  val scene : 'prepared t -> Prismel.Frame.t -> Prismel.Scene.t
  val close : 'prepared t -> unit
  val crash_dump : 'prepared t -> string -> unit
  (** Write the document (a preset) and editor state into a crash report
      folder; pass it as [Sketch.run_state ~crash_dump] when driving the
      editor from your own [run_state]. [run] does this itself. *)
  val graph : 'prepared t -> Procedural.Graph.t
  val document : 'prepared t -> Procedural.Edit_graph.t
  val selected_node : 'prepared t -> Procedural.Node.t option
  val displayed_node : 'prepared t -> Procedural.Node.t
  val prepared : 'prepared t -> 'prepared option
  val camera : 'prepared t -> Prismel.Easy_camera2.t
  val timeline : 'prepared t -> Sketch_support.Timeline.t
  val panes : 'prepared t -> Prismel.Frame.t -> Pxui_shell.Layout.panes

  val run :
    ?layout:layout ->
    ?name:string ->
    ?presets:string ->
    ?timeline_frames:int ->
    ?factories:Procedural.Edit_graph.factory list ->
    ?settings:Settings.t ->
    ?commands:(Pxui_shell.Layout.panel, 'prepared t -> 'prepared t) Editor_core.Command.t list ->
    ?lights:Prismel.Light.t list ->
    ?world:Prismel.World.t ->
    ?camera:Prismel.Easy_camera2.t ->
    ?background:Prismel.Color.t ->
    ?seed:int64 ->
    ?grain:int ->
    ?domains:int ->
    ?max_entries:int ->
    ?max_payload_bytes:int ->
    config:Prismel.Sketch.config ->
    workspace:Workspace_doc.t ->
    prepare:(Settings.t -> Procedural.Session.output -> ('prepared, string) result) ->
    scene2:(Procedural.Graph.t -> 'prepared -> Prismel.Scene.t) ->
    ?overlay:(Procedural.Graph.t -> 'prepared option -> Prismel.Frame.t ->
      Prismel.Scene.t) ->
    ?status:('prepared option -> string option) ->
    unit ->
    unit
end

(** A [.plisp] sketch as a program (plan W11).  Command-S rewrites the file when it is
    still the text the document came from (comments intact), else saves a preset;
    an edit of the file from any editor reloads the running document as one history
    entry, "Reload <file>", and a file that does not check leaves the last good
    document with the diagnostics in the status bar and the text pane. *)
module Workspace : sig
  type source = { path : string; digest : string }
  (** Where a workspace came from: [path] relative to the project root, [digest]
      the SHA-256 of its text. *)

  val load : ?factories:Procedural.Edit_graph.factory list -> string ->
    (Workspace_doc.t, Flow.Diagnostic.t list) result
  (** Parse and check a [.plisp] text against {!workspace_catalog}. *)

  val open_text : ?factories:Procedural.Edit_graph.factory list -> path:string -> digest:string ->
    string -> Workspace_doc.t * Source.t option
  (** For a sketch that has its own [main.ml] (custom renderer, settings, SOPs): [load] the text
      of [path] (its SHA-256 [digest], both from the generated [Sketch_source] module) and find
      the file, so [Editor3.run ~workspace ?source] saves and reloads it like {!main}. On a
      failure it prints the diagnostics and exits 1. *)

  val sop_graphs : ?factories:Procedural.Edit_graph.factory list -> Workspace_doc.t ->
    ((string * Procedural.Graph.t) list, string) result
  (** Every [sop] graph of the document with its result compiled, by name, for cooking without
      an editor (a check, a batch). A graph without a result node is left out. *)

  val run : ?source:source -> Workspace_doc.t -> unit
  (** Open {!Editor3} on the document, with the window title, size, frame rate
      and seed of its settings graph, saving and reloading through [source] (found
      from the executable, then the working directory; without the file the sketch
      runs unwired). *)

  val main : path:string -> digest:string -> catalog:string -> string -> unit
  (** Entry point of a generated [main.ml]: [load] then [run]; on failure prints
      the diagnostics in the OCaml format and exits 1. [catalog] is
      {!Editor_document.Contexts.catalog_digest} at build time; a different
      running catalog is reported and the source checked again. *)
end
