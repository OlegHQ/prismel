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
  val toggle : column -> t -> t
  val expand : column -> t -> t
end

module Chrome : sig
  val update : Layout.t -> Pxui.Ui.t -> Prismel.Frame.t -> Layout.t
  (* A pane's PXUI hit ancestor; children keep screen-space coordinates. *)
  val pane_root : Pxui.Ui.t -> Prismel.Frame.t -> bounds:Layout.bounds ->
    string -> Pxui.Ui.box
  val focus : Pxui.Ui.t -> bounds:Layout.bounds -> unit
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

module Timeline_bar : sig
  type intent = Pause_toggle | Stop_playback | Reset_playback
    | Seek_playback of int64

  val draw : Pxui.Ui.t -> bounds:(int * int * int * int) -> playing:bool ->
    frame:int64 -> time:float -> max_frame:int -> intent list
  (** Draw timeline controls and return playback requests. *)
end

module Prompt : sig
  val name : Pxui.Ui.t -> key:string -> title:string -> label:string ->
    query:string -> (string * Pxui.Ui.pick) option
  val search : Pxui.Ui.t -> key:string -> title:string -> label:string ->
    query:string -> rows:(string -> (string * string) array) ->
    (string * Pxui.Ui.pick) option
  (** Standard name and searchable-picker modals; hosts interpret the result. *)
end

module Shell : sig
  val frame : Pxui.Ui.t -> Prismel.Frame.t -> visible:bool ->
    body:(Pxui.Ui.t -> 'a) -> overlay:(Pxui.Ui.t -> unit) option -> 'a option
  (** Build editor content when visible, and a pending overlay when hidden. *)
end
