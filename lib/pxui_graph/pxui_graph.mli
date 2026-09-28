(** Interactive editor for an immutable [Flow_sop.Network] document.

    The canvas owns selection, search, pan and zoom, and presents the host's
    saved layout. It emits topology, literal and layout requests but never
    compiles or cooks geometry; the host applies
    commands to the document and schedules cooking. *)

type t

type catalog_entry = {
  key : string;
  label : string;
  category : string list;
  arity : int;
  ports : (string * Flow.Port_type.t) list;
}

(** Convert define-once SOP descriptors into the exact entries consumed by
    the node menu. Category paths become nested submenus; no second catalog
    is maintained by the sketch host. *)
val catalog_of_factories :
  Procedural.Edit_graph.factory list -> catalog_entry list

type add_request = {
  factory_key : string;
  inputs : int list;
  source : Flow_sop.Port.t option;
  at : float * float;
}

type insert_request = {
  factory_key : string;
  connection : Procedural.Edit_graph.connection;
  at : float * float;
  ripple : (int * float * float) list;
}

type paste_request = {
  fragment : Flow_sop.Network.fragment;
  positions : (int * float * float) list;
}

type change =
  | Selected of int option
  | Viewed of int
  | View_changed
  | Node_moved of int
  | Nodes_moved of int list
  | Bend_changed of { node : int; slot : int }
  | Level_changed of int list
  | Set_parameter_requested of { node : int; path : string; value : Procedural.Parameter.value }
  | Rename_requested of { node : int; label : string }
  | Split_requested of { node : int; group : string; split : bool }
  | Row_pinned of { node : int; path : string; pinned : bool }
  | Cut_wires_requested of Procedural.Edit_graph.connection list
  | Connection_selected of Procedural.Edit_graph.connection option
  | Connect_requested of { source : Flow_sop.Port.t; consumer : int; input_index : int }
  | Disconnect_requested of Procedural.Edit_graph.connection
  | Value_connect_requested of { source : Flow_sop.Port.t; target : Flow_sop.Port.t }
  | Value_bind_requested of { source : Flow_sop.Port.t; target : Flow_sop.Port.t }
  | Value_disconnect_requested of Flow_sop.Port.t
  | Wireless_changed of { target : Flow_sop.Port.t; wireless : bool }
  | Row_reset_requested of Flow_sop.Port.t
  | Expression_requested of { target : Flow_sop.Port.t; text : string }
  | Fold_requested of Flow_sop.Port.t
  | Unfold_requested of Flow_sop.Port.t
  | Delete_nodes_requested of int list
  | Dissolve_nodes_requested of int list
  | Bypass_requested of (int * bool) list
  | Notice of string
  | Add_requested of add_request
  | Insert_requested of insert_request
  | Paste_requested of paste_request
  | Flag_requested of int
      (** the flag button (or "Set active" menu item) on a [flaggable] tile *)
  | Frame_camera_requested of int
      (** frame the host's viewport camera on this node's cooked bounds *)
  | Open_requested of int
      (** a tile was double-clicked: the host may enter the node *)

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
  ?enterable:(Procedural.Edit_graph.node_info -> bool) ->
  Procedural.Graph.t -> t

val create_document :
  ?x:int -> ?y:int -> ?width:int -> ?height:int ->
  ?theme:Pxui.theme -> ?selected:int ->
  ?catalog:catalog_entry list -> ?flaggable:(Procedural.Edit_graph.node_info -> bool) ->
  ?enterable:(Procedural.Edit_graph.node_info -> bool) ->
  ?namespace:string ->
  ?definitions:Flow_sop.Network.definition Flow_sop.Network.String_map.t ->
  Flow_sop.Network.t -> t
(** Present a Flow network, including geometry and value tiles and typed wires.
    [flaggable] marks tiles that get a flag button (default: none); the
    graph never interprets operation names itself. *)

val with_document : Flow_sop.Network.t -> t -> t
val with_definitions : Flow_sop.Network.definition Flow_sop.Network.String_map.t -> t -> t

(** Live, normalized values resolved by the host before cooking. *)
val with_applied : Flow.Port_type.value Flow_sop.Port.Map.t -> t -> t
val with_graph : Procedural.Graph.t -> t -> t
val with_bounds : x:int -> y:int -> width:int -> height:int -> t -> t
val with_visible : bool -> t -> t
val with_guide : bool -> t -> t
val hovered_row : t -> (int * string) option
(** The parameter row owning PXUI hover after the last update. *)

val visible : t -> bool

val selected : t -> int option
val selected_nodes : t -> int list
val selected_connection : t -> Procedural.Edit_graph.connection option
val selected_wire : t -> bool
val showing_wireless : t -> bool
val viewed : t -> int
val flagged : t -> int option
val with_flagged : int option -> t -> t
(** The flagged tile (e.g. the active render camera). The host owns it and
    re-applies it every frame, like the document. *)

val select : int -> t -> t
val select_nodes : int list -> t -> t
val clear_selection : t -> t
val view : int -> t -> t
val place_nodes : (int * float * float) list -> t -> t
(** Move tiles to graph-space [(id, x, y)] positions in one rebuild; ids not
    in the graph are ignored. *)

val node_views : t -> node_view list

val trunk : Procedural.Edit_graph.t -> (int * int * bool) array
(** The network as list rows [(id, depth, link)], sources first: rows follow
    each node's first input, other inputs nest one level under the node that
    consumes them, and a node reached twice repeats as a [link] row. *)

val node_positions : t -> (int * float * float) list
(** Graph-space tile positions of every node, the inverse of {!place_nodes}. *)

val node_position : t -> int -> (float * float) option
(** One tile's graph-space position, without walking the graph. *)

val layout : t -> Editor_core.Network_layout.t
val with_layout : Editor_core.Network_layout.t -> t -> t
val set_wireless : target:Flow_sop.Port.t -> wireless:bool -> t -> t
val edit_layout : nodes:int list -> ports:(int * string) list ->
  t -> Editor_core.Network_layout.t -> Editor_core.Network_layout.t
val set_bends : node:int -> slot:int -> (float * float) list -> t -> t
val set_split : node:int -> group:string -> split:bool -> t -> t
val set_row_pin : node:int -> path:string -> pinned:bool -> t -> t

val open_menu_at : int * int -> t -> t
(** Open the hierarchical node menu at a screen point (clamped inside the
    canvas). With a selected wire it offers nodes with a primary input for insertion. *)

val optimize_layout : t -> t
(** Re-run automatic layout, dropping manual tile positions, and frame all. *)

val frame_viewed : t -> t
(** Frame the displayed tile, or all tiles when it is unavailable. *)

val with_last_added : string -> t -> t
val carry_last_added : from:t -> t -> t
(** Retain the last qualified kind across host level changes. *)

val hinting : t -> bool
val editing : t -> bool

val copy_selection : t -> t
val delete_selection : t -> t * change list
(** Graph commands return topology requests for the host to apply. *)

val stats : t -> stats

type direction = Left | Down | Up | Right
type command = Copy | Cut | Paste | Duplicate | Delete | Frame_all
  | Open_detail | Point_detail | Open_all | Point_all
  | Walk of direction | Add | Repeat | Connect_hint | Bind_hint | Show_wireless
  | Row_reset | Row_expression
  | Display | Mute | Dissolve | Find
  | Frame_selection | Row_pin | Hint_letter of char | Hint_back | Cancel
val hint_bindings : ('scope, command) Editor_core.Command.t list
val bindings : ('scope, command) Editor_core.Command.t list
(* Global key commands; the host scopes them to its graph pane. *)
val run_command : ?at:(int * int) -> t -> command -> t * change list
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
      {!frame_viewed}, and {!open_menu_at} (Prismel_editor: layout through the
      context menu or palette; leader [f] frames and [a] opens the menu);
    - the hierarchical node menu: category paths form submenus,
      while typed search matches labels, keys, and complete breadcrumbs across
      the entire catalog; on a selected wire it offers nodes with a primary input for
      atomic insertion. *)
val update : t -> Pxui.Ui.t -> Prismel.Frame.t -> t * change list
(** Build the canvas inside [Pxui.Ui.frame], at the root level, and return
    this frame's commands. Pointer capture comes from the UI: the canvas and
    each visible tile (keyed by node id) are boxes, while the graph's spatial
    index still culls tiles and resolves wire and input-port hits. Wires are
    polylines; the dot grid is one quad. *)

module Private : sig
  val menu_keys : t -> query:string -> string array
  val hint_labels : t -> (string * int * int option) list
  val zoom : t -> float
  val level : t -> int -> Editor_core.Network_layout.level option
  val field_bounds : t -> node:int -> path:string -> (int * int * int * int) option
  val crossed_wires : t -> int * int -> int * int -> Procedural.Edit_graph.connection list
  val hit_edge_id : t -> int * int -> Procedural.Edit_graph.connection option
  val edge_query_points : t -> limit:int -> (int * int) array
  val hit_edge_candidates : t -> int * int -> int
end
