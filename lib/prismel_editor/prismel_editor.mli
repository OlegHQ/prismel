(** Reusable graph-driven procedural sketch environments.

    Both environments share a responsive view/graph/inspector workspace,
    persistent graph navigation, generated node inspection, bounded
    asynchronous cooking, status UI, and finite native execution. Their thin
    adapters own only the dimensional camera, viewport composition, and
    still-image renderer. Overlay callbacks receive a frame and coordinates
    local to the current view pane. *)

module Preset = Preset

type layout = Pxui_shell.Layout.config = {
  view_ratio : float;
  graph_ratio : float;
  inspector_ratio : float;
  splitter_width : int;
  collapsed_width : int;
  header_height : int;
  status_height : int;
  min_view_width : int;
  min_graph_width : int;
  min_inspector_width : int;
}

(** Default 45% view, 35% graph, and 20% inspector proportions. *)
val default_layout : layout

(** Workspace compatibility facade and leader-key internals, exposed for tests.
    Layout and chrome live in [Pxui_shell]; sketches use [Editor3]/[2]. *)
module Private : sig
  module Workspace : sig
    type column = View | Graph | Inspector | Timeline
    (** [Timeline] is the full-width bottom bar, collapsed (hidden) by default. *)

    type bounds = int * int * int * int
    type t

    type panes = {
      view : bounds;
      graph : bounds;
      inspector : bounds;
      status : bounds;
      timeline : bounds;  (** zero height while collapsed *)
      view_header : bounds;
      graph_header : bounds;
      inspector_header : bounds;
    }

    val create : layout -> t
    val geometry : t -> Prismel.Frame.t -> panes
    val collapsed : t -> column -> bool
    val toggle : column -> t -> t
    val expand : column -> t -> t

    (** Build and paint the workspace chrome inside [Pxui.Ui.frame]: pane
        backgrounds, resize splitters, and header bars with collapse buttons.
        Splitter proportions survive subsequent resizes. *)
    val update : t -> Pxui.Ui.t -> Prismel.Frame.t -> t
  end

  (** Helix-style leader keys. Space (while no text field is focused) opens a
      centered which-key panel; the next key runs a binding from the global
      scope or from the focused pane, the one last clicked. Escape, Space, an
      unknown key, a click, or window focus loss cancel it. *)
  module Leader : sig
    type action =
      | Save_preset | Browse_presets
      | Toggle_timeline | Toggle_graph | Toggle_inspector | Hide_ui | Open_camera
      | Play_pause | Reset | Stop
      | Add_node | Layout | Frame_tile | Frame_camera
      | Look_through | Fly
      | Undo | Redo
      | Graph_command of Pxui_graph.command

    type binding = (Workspace.column, action) Editor_core.Keymap.binding

    type state = Editor_core.Router.state = Idle | Pending

    val keymap : binding list
    (** The single table behind dispatch and the which-key panel. *)

    val keymap3 : binding list
    (** [keymap] plus the 3D view bindings ([w] fly, [v] look through). *)

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
      primary-pointer edit is held, only the latest desired cook is retained. *)
  module Schedule : sig
    type t
    val initial : t
    val step :
      t -> graph:Procedural.Graph.t -> effects:Procedural.Parameter.effects ->
      context_changed:bool -> force:bool -> busy:bool -> frame:Prismel.Frame.t ->
      t * bool
  end
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
    ?camera:Prismel.Easy_camera.t ->
    ?background:Prismel.Color.t ->
    ?seed:int64 ->
    ?grain:int ->
    ?domains:int ->
    ?max_entries:int ->
    ?max_payload_bytes:int ->
    graph:Procedural.Graph.t ->
    prepare:(Procedural.Session.output -> ('prepared, string) result) ->
    scene3:(Procedural.Graph.t -> 'prepared -> Prismel.Scene3.t) ->
    ?overlay:(Procedural.Graph.t -> 'prepared option -> Prismel.Frame.t ->
      Prismel.Scene.t) ->
    unit ->
    ('prepared t, string) result
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

  val rerender : 'prepared t -> 'prepared t
  (** Re-evaluates [scene3] now and forces a recook so [prepare] runs again,
      for sketch-owned render settings (such as a renderer toggle) that live
      outside the graph's parameter effects and may be read by [prepare]. *)

  (** The workspace keeps one [Editor_core.History] history of the editable document:
      graph edits and inspector commits are entries, continuous slider drags
      collapse into one, and Command/Ctrl-Z, Shift-Command/Ctrl-Z, and
      Ctrl-Y step it. *)
  val can_undo : 'prepared t -> bool
  val can_redo : 'prepared t -> bool
  val scene : 'prepared t -> Prismel.Frame.t -> Prismel.Scene.t
  val close : 'prepared t -> unit
  val graph : 'prepared t -> Procedural.Graph.t
  val document : 'prepared t -> Procedural.Edit_graph.t
  val selected_node : 'prepared t -> Procedural.Node.t option
  val displayed_node : 'prepared t -> Procedural.Node.t
  val prepared : 'prepared t -> 'prepared option
  val camera : 'prepared t -> Prismel.Easy_camera.t
  (** The interactive viewport camera. *)

  val render_camera : 'prepared t -> Prismel.Camera.t
  (** The ACTIVE camera node's view (the viewport camera when the document has
      no camera node). Camera nodes are SOPs with operation ["camera"], such
      as [Sop_catalog.Camera]; when [factories] offers one, a default camera
      following the viewport is added to a document without one, and again if
      the last is deleted (inside the same undo entry). With follow viewport
      on, viewport motion writes the node (one undo entry per gesture) and
      node edits or undo move the viewport. Renderers, PNG export, and
      look-through use it. *)

  val flying : 'prepared t -> bool
  (** [Space w] with the view focused: held W/S/A/D/Q/E fly the viewport
      camera ([Easy_camera.fly]) with the pointer captured through
      [Sketch.set_relative_mouse]. Escape or focus loss exits; Space exits and
      opens the leader. *)

  val look_through : 'prepared t -> bool
  (** The view shows [render_camera] ([Space v], or the Camera panel toggle);
      orbit input is frozen unless the active camera follows the viewport. *)

  val timeline : 'prepared t -> Sketch_support.Timeline.t
  val panes : 'prepared t -> Prismel.Frame.t -> Private.Workspace.panes
  val graph_nodes : 'prepared t -> Pxui_graph.node_view list

  val run :
    ?layout:layout ->
    ?name:string ->
    ?presets:string ->
    ?timeline_frames:int ->
    ?factories:Procedural.Edit_graph.factory list ->
    ?camera:Prismel.Easy_camera.t ->
    ?background:Prismel.Color.t ->
    ?seed:int64 ->
    ?grain:int ->
    ?domains:int ->
    ?max_entries:int ->
    ?max_payload_bytes:int ->
    config:Prismel.Sketch.config ->
    graph:Procedural.Graph.t ->
    prepare:(Procedural.Session.output -> ('prepared, string) result) ->
    scene3:(Procedural.Graph.t -> 'prepared -> Prismel.Scene3.t) ->
    ?overlay:(Procedural.Graph.t -> 'prepared option -> Prismel.Frame.t ->
      Prismel.Scene.t) ->
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
    ?camera:Prismel.Easy_camera2.t ->
    ?background:Prismel.Color.t ->
    ?seed:int64 ->
    ?grain:int ->
    ?domains:int ->
    ?max_entries:int ->
    ?max_payload_bytes:int ->
    graph:Procedural.Graph.t ->
    prepare:(Procedural.Session.output -> ('prepared, string) result) ->
    scene2:(Procedural.Graph.t -> 'prepared -> Prismel.Scene.t) ->
    ?overlay:(Procedural.Graph.t -> 'prepared option -> Prismel.Frame.t ->
      Prismel.Scene.t) ->
    unit ->
    ('prepared t, string) result

  val update : 'prepared t -> Prismel.Frame.t -> 'prepared t
  val update_with :
    'prepared t -> Prismel.Frame.t -> inspector:(Pxui.Ui.t -> 'a) ->
    'prepared t * 'a option
  (** [update], also building sketch-owned widgets in the unselected inspector.
      The result is [None] when that panel is not built. *)

  (* Call from [Sketch.run_state ~after_present] when driving the environment
      manually so PNG requests save the completed frame. *)
  val after_present : 'prepared t -> Prismel.Frame.t -> 'prepared t
  (* Re-evaluates [scene2] now and forces [prepare] to run again for
      sketch-owned render settings outside graph parameter effects. *)
  val rerender : 'prepared t -> 'prepared t
  val can_undo : 'prepared t -> bool
  val can_redo : 'prepared t -> bool
  val scene : 'prepared t -> Prismel.Frame.t -> Prismel.Scene.t
  val close : 'prepared t -> unit
  val graph : 'prepared t -> Procedural.Graph.t
  val document : 'prepared t -> Procedural.Edit_graph.t
  val selected_node : 'prepared t -> Procedural.Node.t option
  val displayed_node : 'prepared t -> Procedural.Node.t
  val prepared : 'prepared t -> 'prepared option
  val camera : 'prepared t -> Prismel.Easy_camera2.t
  val timeline : 'prepared t -> Sketch_support.Timeline.t
  val panes : 'prepared t -> Prismel.Frame.t -> Private.Workspace.panes
  val graph_nodes : 'prepared t -> Pxui_graph.node_view list

  val run :
    ?layout:layout ->
    ?name:string ->
    ?presets:string ->
    ?timeline_frames:int ->
    ?factories:Procedural.Edit_graph.factory list ->
    ?camera:Prismel.Easy_camera2.t ->
    ?background:Prismel.Color.t ->
    ?seed:int64 ->
    ?grain:int ->
    ?domains:int ->
    ?max_entries:int ->
    ?max_payload_bytes:int ->
    config:Prismel.Sketch.config ->
    graph:Procedural.Graph.t ->
    prepare:(Procedural.Session.output -> ('prepared, string) result) ->
    scene2:(Procedural.Graph.t -> 'prepared -> Prismel.Scene.t) ->
    ?overlay:(Procedural.Graph.t -> 'prepared option -> Prismel.Frame.t ->
      Prismel.Scene.t) ->
    unit ->
    unit
end
