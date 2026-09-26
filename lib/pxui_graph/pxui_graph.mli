(** Interactive editor for an immutable [Procedural.Edit_graph] document.

    The canvas owns selection, search, and graph-space positions. It emits
    topology commands but never compiles or cooks geometry; the host applies
    commands to the document and schedules cooking. *)

type t

type catalog_entry = {
  key : string;
  label : string;
  category : string list;
  arity : int;
}

(** Convert define-once SOP descriptors into the exact entries consumed by
    the node menu. Category paths become nested submenus; no second catalog
    is maintained by the sketch host. *)
val catalog_of_factories :
  Procedural.Edit_graph.factory list -> catalog_entry list

type add_request = {
  factory_key : string;
  inputs : int list;
  at : float * float;
}

type insert_request = {
  factory_key : string;
  connection : Procedural.Edit_graph.connection;
  at : float * float;
}

type paste_request = {
  fragment : Procedural.Edit_graph.fragment;
  positions : (int * float * float) list;
}

type change =
  | Selected of int option
  | Viewed of int
  | View_changed
  | Node_moved of int
  | Nodes_moved of int list
  | Connection_selected of Procedural.Edit_graph.connection option
  | Connect_requested of Procedural.Edit_graph.connection
  | Disconnect_requested of Procedural.Edit_graph.connection
  | Delete_nodes_requested of int list
  | Add_requested of add_request
  | Insert_requested of insert_request
  | Paste_requested of paste_request
  | Flag_requested of int
      (** the flag button (or "Set active" menu item) on a [flaggable] tile *)
  | Frame_camera_requested of int
      (** frame the host's viewport camera on this node's cooked bounds *)

type node_view = {
  id : int;
  label : string;
  operation : string;
  depth : int;
  bounds : int * int * int * int;
  view_bounds : int * int * int * int;
  selected : bool;
  viewed : bool;
  active : bool;
  active_bounds : (int * int * int * int) option;  (** camera tiles only *)
  has_parameters : bool;
}

type stats = {
  nodes : int;
  wires : int;
  visible_nodes : int;
  visible_wires : int;
  spatial_cells : int;
  max_spatial_candidates : int;
  spatial_edge_cells : int;
  max_spatial_edge_candidates : int;
  overflow_spatial_edges : int;
}

val create :
  ?x:int -> ?y:int -> ?width:int -> ?height:int ->
  ?theme:Pxui.theme -> ?selected:int ->
  ?catalog:catalog_entry list -> ?flaggable:(Procedural.Edit_graph.node_info -> bool) ->
  Procedural.Graph.t -> t

val create_document :
  ?x:int -> ?y:int -> ?width:int -> ?height:int ->
  ?theme:Pxui.theme -> ?selected:int ->
  ?catalog:catalog_entry list -> ?flaggable:(Procedural.Edit_graph.node_info -> bool) ->
  Procedural.Edit_graph.t -> t
(** [flaggable] marks tiles that get a flag button (default: none); the
    graph never interprets operation names itself. *)

val with_document : Procedural.Edit_graph.t -> t -> t
val with_graph : Procedural.Graph.t -> t -> t
val with_bounds : x:int -> y:int -> width:int -> height:int -> t -> t
val with_visible : bool -> t -> t
val visible : t -> bool

val selected : t -> int option
val selected_nodes : t -> int list
val selected_connection : t -> Procedural.Edit_graph.connection option
val viewed : t -> int
val flagged : t -> int option
val with_flagged : int option -> t -> t
(** The flagged tile (e.g. the active render camera). The host owns it and
    re-applies it every frame, like the document. *)

val select : int -> t -> t
val select_nodes : int list -> t -> t
val clear_selection : t -> t
val view : int -> t -> t
val place_node : node_id:int -> x:float -> y:float -> t -> t
val node_views : t -> node_view list

val node_positions : t -> (int * float * float) list
(** Graph-space tile positions of every node, the inverse of {!place_node}. *)

val open_menu_at : int * int -> t -> t
(** Open the hierarchical node menu at a screen point (clamped inside the
    canvas). With a selected wire it offers one-input nodes for insertion. *)

val optimize_layout : t -> t
(** Re-run automatic layout, dropping manual tile positions, and frame all. *)

val frame_viewed : t -> t
(** Frame the displayed tile, or all tiles when it is unavailable. *)

val copy_selection : t -> t
val delete_selection : t -> t * change list
(** Graph commands return topology requests for the host to apply. *)

val stats : t -> stats

type command = Copy | Cut | Paste | Duplicate | Delete | Frame_all
val bindings : (Editor_core.Keymap.trigger * string * command) list
val run_command : t -> command -> t * change list
(** Commands are dispatched by the host's key router, not by [update]. *)

(** Interaction contract:

    - left-click selects; Shift-click and blank-area marquee form multi-select;
    - dragging any selected tile moves the whole selection;
    - output-port drag to an input emits a validated connection request;
    - a wire can be selected and deleted, or used as the insertion context;
    - Delete/Backspace removes selected nodes or the selected wire;
    - Command/Ctrl-C, -V, and -X copy, paste, and cut selected subgraphs;
      Command/Ctrl-D duplicates them with fresh logical node IDs;
    - [Home] frames all; the host binds {!optimize_layout},
      {!frame_viewed}, and {!open_menu_at} (Prismel_editor: leader [l], [f], [a]);
    - the hierarchical node menu: category paths form submenus,
      while typed search matches labels, keys, and complete breadcrumbs across
      the entire catalog; on a selected wire it offers one-input nodes for
      atomic insertion. *)
val update : t -> Pxui.Ui.t -> Prismel.Frame.t -> t * change list
(** Build the canvas inside [Pxui.Ui.frame], at the root level, and return
    this frame's commands. Pointer capture comes from the UI: the canvas and
    each visible tile (keyed by node id) are boxes, while the graph's spatial
    index still culls tiles and resolves wire and input-port hits. Wires are
    cubic Béziers; the dot grid is one quad. *)

module Private : sig
  val hit_edge_id : t -> int * int -> Procedural.Edit_graph.connection option
  val edge_query_points : t -> limit:int -> (int * int) array
  val hit_edge_candidates : t -> int * int -> int
end
