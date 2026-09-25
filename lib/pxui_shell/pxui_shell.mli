(** Editor chrome built with the shared PXUI handle. *)

module Layout : sig
  type config = {
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

  val default : config
  (** 45% view, 35% graph, 20% inspector. *)

  type column = View | Graph | Inspector | Timeline
  type bounds = int * int * int * int
  type panes = {
    view : bounds;
    graph : bounds;
    inspector : bounds;
    status : bounds;
    timeline : bounds;
    view_header : bounds;
    graph_header : bounds;
    inspector_header : bounds;
  }
  type t

  val create : config -> t
  val geometry : t -> Prismel.Frame.t -> panes
  val collapsed : t -> column -> bool
  val with_collapsed : column -> bool -> t -> t
  val toggle : column -> t -> t
  val expand : column -> t -> t
end

module Chrome : sig
  val update : Layout.t -> Pxui.Ui.t -> Prismel.Frame.t -> Layout.t
  val floating : Pxui.Ui.t -> ?flags:Pxui.Ui.flags -> Layout.bounds -> string ->
    Pxui.Ui.box
end

module Which_key : sig
  val panel : Pxui.Ui.t -> ('scope, 'action) Editor.Keymap.binding list ->
    focus:'scope -> focus_name:string -> unit
  (** Draw global and focused leader bindings in the standard modal. *)
end

module Status_bar : sig
  val draw : Pxui.Ui.t -> bounds:(int * int * int * int) ->
    text:string -> fps:int option -> unit
  (** Paint the standard status strip in logical-point bounds. *)
end
