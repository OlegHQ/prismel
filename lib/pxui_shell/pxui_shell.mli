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
  val sheet : Pxui.Ui.t -> ('scope, 'action) Editor_core.Command.t list -> bool
  (** Grouped Flow key table. False on dismissal or Close. *)

  val panel : Pxui.Ui.t -> ('scope, 'action) Editor_core.Command.t list ->
    prefix:string -> focus:'scope -> focus_name:string -> unit
  (** Draw the page of global and focused commands whose leader sequence
      continues [prefix] (plus key chords on the first page) in the standard
      modal; a key leading to several commands shows as a [+group] row. *)
end

module Status_bar : sig
  val guide : Pxui.Ui.t -> bounds:Layout.bounds -> context:Editor_core.Guide_context.t ->
    ('scope, 'action) Editor_core.Command.t list -> bool
  (** Context and applicable keys in table order; true when Hide is clicked. *)

  val hud : Pxui.Ui.t -> bounds:Layout.bounds -> text:string -> unit
  (** Noninteractive key feedback in the pane's bottom corner. *)

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

(** A keyboard-first tree list (WAI-ARIA treeview keys): focus is separate
    from selection, folds and a filter (keeping ancestors) are view state,
    rows show indent guides and sticky ancestors, toggle columns paint when
    dragged, and rows drag with a 4-point dead zone onto before/inside/after
    drop zones. A right-click menu (enter, rename, hide, delete) acts on the
    row, or on the selection when the row is in it, without changing the
    selection. The host owns rows and selection and applies the intents. *)
module Tree : sig
  type row = {
    id : int;
    depth : int;  (** depth-first order; a child is one deeper than its parent *)
    label : string;
    detail : string;  (** muted text after the label, e.g. the kind *)
    badge : string * Prismel.Color.t;  (** a kind letter on its colour *)
    link : bool;  (** a muted [↳] row repeating [id] shown elsewhere *)
    ghost : bool;  (** dimmed and locked: no rename, drag, or toggles *)
    flags : bool list;  (** one per column *)
  }
  type drop = Before | Inside | After
  type intent =
    | Select of int list  (** the new selection, primary first *)
    | Flag of { ids : int list; column : int; value : bool }
    | Move of { ids : int list; target : int; drop : drop }
    | Indent of int list
    | Outdent of int list
    | Reorder of { ids : int list; delta : int }
    | Rename of int * string
    | Activate of int  (** double-click, or the host's enter key *)
    | Delete of int list  (** from the row context menu *)
  type command = Up | Down | Extend_up | Extend_down | Collapse | Expand
    | First | Last | Indent_rows | Outdent_rows | Move_up | Move_down
    | Rename_row | Filter | Hide | Activate_row
  type t

  val create : unit -> t
  val bindings : ('scope, command) Editor_core.Command.t list
  (** Arrows, Home/End, Tab/Shift-Tab, Alt-arrows, F2, [/], [h], Enter; the host
      scopes them to its list pane. *)

  val run_command : t -> row array -> selected:int list -> command -> t * intent list
  val update : t -> Pxui.Ui.t -> Prismel.Frame.t -> bounds:(int * int * int * int) ->
    ?title:string -> columns:string list -> row array -> selected:int list -> t * intent list
  (** Build the list inside [Ui.frame] and return this frame's intents;
      [title] leads the header, e.g. the level's breadcrumb. *)

  val rename : int -> string -> t -> t
  (** Open the rename prompt on a row, e.g. one just added. *)

  val reveal : t -> t
  (** Scroll the focused row into view on the next update. *)

  val focused : t -> int option
  val editing : t -> bool
  (** The filter or rename prompt holds the keyboard. *)
end

module Shell : sig
  val frame : Pxui.Ui.t -> Prismel.Frame.t -> visible:bool ->
    body:(Pxui.Ui.t -> 'a) -> overlay:(Pxui.Ui.t -> unit) option -> 'a option
  (** Build editor content when visible, and a pending overlay when hidden. *)
end

(** Parameter rows generated from [Editor_core.Param] metadata: the one
    inspector path for SOP nodes and plain sketch settings alike. *)
module Inspector : sig
  type flow_row = {
    path : string;
    fields : Editor_core.Param.field_view list;
    shown : bool;
    locked : bool;
    drive : string option;
    live : string option;
    components : (string * string * string option) list;
    split : bool option;
  }
  type flow_change = Edited of string * Editor_core.Param.value
    | Pinned of string * bool | Split of string * bool | Reset of string
    | Expression of string * string
  val flow_fields : Pxui.Ui.t -> ?expanded:string list -> flow_row list -> flow_change list

  val fields : Pxui.Ui.t -> ?expanded:string list ->
    Editor_core.Param.field_view list -> (string * Editor_core.Param.value) list
  (** One kit widget per field inside the current panel; folders become
      accordions, open when their ["/"]-joined path is in [expanded]. Returns
      this frame's edits, empty when nothing changed. *)

  val record : Pxui.Ui.t -> ?expanded:string list ->
    'record Editor_core.Param.schema -> 'record ->
    ('record * Editor_core.Param.effects, string) result
  (** [fields] over a typed record, edits applied through [Param.apply_all]. *)
end
