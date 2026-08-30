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
    the Space menu. Category paths become nested submenus; no second catalog
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
  | Layout_optimized

type node_view = {
  id : int;
  label : string;
  operation : string;
  depth : int;
  bounds : int * int * int * int;
  view_bounds : int * int * int * int;
  selected : bool;
  viewed : bool;
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
  ?catalog:catalog_entry list -> Procedural.Graph.t -> t

val create_document :
  ?x:int -> ?y:int -> ?width:int -> ?height:int ->
  ?theme:Pxui.theme -> ?selected:int ->
  ?catalog:catalog_entry list -> Procedural.Edit_graph.t -> t

val document : t -> Procedural.Edit_graph.t
val with_document : Procedural.Edit_graph.t -> t -> t
val with_graph : Procedural.Graph.t -> t -> t
val with_catalog : catalog_entry list -> t -> t
val with_bounds : x:int -> y:int -> width:int -> height:int -> t -> t
val with_visible : bool -> t -> t
val visible : t -> bool

val selected : t -> int option
val selected_nodes : t -> int list
val selected_connection : t -> Procedural.Edit_graph.connection option
val viewed : t -> int
val select : int -> t -> t
val select_nodes : int list -> t -> t
val clear_selection : t -> t
val view : int -> t -> t
val place_node : node_id:int -> x:float -> y:float -> t -> t
val node_views : t -> node_view list
val stats : t -> stats

(** Interaction contract:

    - left-click selects; Shift-click and blank-area marquee form multi-select;
    - dragging any selected tile moves the whole selection;
    - output-port drag to an input emits a validated connection request;
    - a wire can be selected and deleted, or used as the insertion context;
    - Delete/Backspace removes selected nodes or the selected wire;
    - Command/Ctrl-C, -V, and -X copy, paste, and cut selected subgraphs;
      Command/Ctrl-D duplicates them with fresh logical node IDs;
    - [O] optimizes and frames layout, [Home] frames all, [F] frames selection;
    - Space opens the hierarchical node menu. Category paths form submenus,
      while typed search matches labels, keys, and complete breadcrumbs across
      the entire catalog; on a selected wire it offers one-input nodes for
      atomic insertion. *)
val update : t -> Prismel.Frame.t -> t * change list
val scene : t -> Prismel.Scene.t

module Private : sig
  val hit_node_id : t -> int * int -> int option
  val hit_edge_id : t -> int * int -> Procedural.Edit_graph.connection option
  val edge_query_points : t -> limit:int -> (int * int) array
  val hit_candidates : t -> int * int -> int
  val hit_edge_candidates : t -> int * int -> int
end
