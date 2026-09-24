(** Reusable graph-driven procedural sketch environments.

    Both environments share a responsive view/graph/inspector workspace,
    persistent graph navigation, generated node inspection, bounded
    asynchronous cooking, status UI, and finite native execution. Their thin
    adapters own only the dimensional camera, viewport composition, and
    still-image renderer. Overlay callbacks receive a frame and coordinates
    local to the current view pane. *)

type layout = {
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

(** Default 42% view, 33% graph, and 25% inspector proportions. *)
val default_layout : layout

module Workspace : sig
  type column = View | Graph | Inspector
  type bounds = int * int * int * int
  type t

  type panes = {
    view : bounds;
    graph : bounds;
    inspector : bounds;
    status : bounds;
    view_header : bounds;
    graph_header : bounds;
    inspector_header : bounds;
  }

  val create : layout -> t
  val geometry : t -> Prismel.Frame.t -> panes
  val collapsed : t -> column -> bool
  val with_collapsed : column -> bool -> t -> t
  val toggle : column -> t -> t
  val expand : column -> t -> t

  (** Build and paint the workspace chrome inside [Pxui.Ui.frame]: pane
      backgrounds, resize splitters, header bars with collapse buttons, and
      the graph/inspector shortcuts [G]/[I]. Splitter proportions survive
      subsequent resizes. *)
  val update : t -> Pxui.Ui.t -> Prismel.Frame.t -> t
end

module Environment3 : sig
  type 'prepared t
  type nonrec layout = layout
  val default_layout : layout

  val create :
    ?layout:layout ->
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
  val after_present : 'prepared t -> Prismel.Frame.t -> unit

  val rerender : 'prepared t -> 'prepared t
  (** Re-evaluates [scene3] on the current prepared value, for sketch-owned
      render settings (such as a renderer toggle) that live outside the
      graph's parameter effects. *)

  (** The workspace keeps one [Pxui.Undo] history of the editable document:
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
  val timeline : 'prepared t -> Sketch_support.Timeline.t
  val panes : 'prepared t -> Prismel.Frame.t -> Workspace.panes
  val graph_nodes : 'prepared t -> Pxui_graph.node_view list

  val run :
    ?layout:layout ->
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

module Environment2 : sig
  type 'prepared t
  type nonrec layout = layout
  val default_layout : layout

  val create :
    ?layout:layout ->
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
  (* Call from [Sketch.run_state ~after_present] when driving the environment
      manually so PNG requests save the completed frame. *)
  val after_present : 'prepared t -> Prismel.Frame.t -> unit
  val scene : 'prepared t -> Prismel.Frame.t -> Prismel.Scene.t
  val close : 'prepared t -> unit
  val graph : 'prepared t -> Procedural.Graph.t
  val document : 'prepared t -> Procedural.Edit_graph.t
  val selected_node : 'prepared t -> Procedural.Node.t option
  val displayed_node : 'prepared t -> Procedural.Node.t
  val prepared : 'prepared t -> 'prepared option
  val camera : 'prepared t -> Prismel.Easy_camera2.t
  val timeline : 'prepared t -> Sketch_support.Timeline.t
  val panes : 'prepared t -> Prismel.Frame.t -> Workspace.panes
  val graph_nodes : 'prepared t -> Pxui_graph.node_view list

  val run :
    ?layout:layout ->
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
