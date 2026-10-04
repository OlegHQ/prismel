(** Editor chrome built with the shared PXUI handle. *)

(** The shell's panels as a tree ({!Editor_core.Panels}) and its geometry.  A run of
    splits along one axis is one row of columns, so the default three columns
    divide the width once: 45/35/20 of what the two one-point splitters leave. *)
module Layout : sig
  type panel = Editor_core.Panels.panel =
    | View of string | Graph | List | Lisp | Inspector | Outline | Timeline
  type axis = Editor_core.Panels.axis
  type t = Editor_core.Panels.t =
    | Leaf of panel
    | Split of { axis : axis; ratio : float; a : t; b : t }
    | Tile of t list
    | Float of t
  type path = int list
  type bounds = int * int * int * int

  val default : t

  type leaf = { path : path; panel : panel; header : bounds; body : bounds; floating : bool }
  (** One panel: its 22-point header and the body below it.  The body of the
      first viewport stops above the status strip. [floating] covers both authored
      [Float] trees and panels undocked through saved window state. *)

  type splitter = { node : path option; axis : axis; bounds : bounds; start : int; span : int }
  (** A gutter.  [node] is the split it resizes (none for a tile's fixed gutters);
      [start] and [span] are the extent, along [axis], of the columns that split
      divides, so a pointer position maps to a ratio. *)

  type geometry = { leaves : leaf list; splitters : splitter list; status_at : bounds;
                    timeline_at : bounds }
  (** Leaves in tree order, floats last (drawn over the rest). *)

  val geometry : ?state:(path -> Editor_core.Panels.state) -> ?hidden:panel list -> t -> Rays.Frame.t -> geometry
  (** [top] (default 0) points are left above the tree for a host bar.
      [hidden] (default the timeline) panels vanish; a hidden viewport keeps a
      28-point strip with its expand button.  The timeline strip sits under the
      tree unless the tree has a [Timeline] leaf.  Every point of the frame above
      the timeline strip is covered exactly once, floats aside. *)

  val toggle : panel -> panel list -> panel list
  val expand : panel -> panel list -> panel list

  type panes = { view : bounds; graph : bounds; inspector : bounds; status : bounds;
                 timeline : bounds }
  val panes : geometry -> panes
  (** The bodies of the first viewport, graph and inspector panels (all zero when
      absent): what a host names its panes by. *)

  val find : geometry -> panel -> leaf option
  val first_view : geometry -> leaf option
end

module Chrome : sig
  type intent =
    | Resize of { node : Layout.path; ratio : float }  (** a splitter is being dragged ({!splitters}) *)
    | Settled  (** the drag ended *)
    | Toggle of Layout.path  (** a header's collapse button *)
    | Window of Layout.path * Layout.bounds option  (** undock, move/resize, or dock a panel *)
    | Window_drag of Layout.path * Layout.bounds * bool
        (** Transient bounds; [true] commits the released gesture. *)
    | Dragging of Layout.path * bool  (** a panel drag; [true] on release *)
    | Dock_panel of Layout.path * Layout.path * [ `Left | `Right | `Top | `Bottom ]
    | Split_panel of Layout.path * Layout.axis  (** the header menu *)
    | Close_panel of Layout.path
    | Retype_panel of Layout.path * Layout.panel  (** [View ""] means a viewport *)

  val update : ?state:(Layout.path -> Editor_core.Panels.state) -> ?hidden:Layout.panel list -> ?title:(Layout.leaf -> string) -> Layout.t ->
    Pxui.Ui.t -> Rays.Frame.t -> intent list
  (** Panel backgrounds, the drawn gutters, headers with their collapse button and
      right-click menu.  Pure: the host applies the intents. *)

  val splitters : ?state:(Layout.path -> Editor_core.Panels.state) -> ?hidden:Layout.panel list -> Layout.t -> Pxui.Ui.t -> Rays.Frame.t ->
    intent list
  (** The gutters' drag targets, wider than they are drawn ([Resize], [Settled]).  Call it
      after the panes' boxes so a gutter is not shadowed by its neighbours' hit areas. *)

  (* A pane's PXUI hit ancestor; children keep screen-space coordinates. *)
  val pane_root : Pxui.Ui.t -> Rays.Frame.t -> bounds:Layout.bounds ->
    string -> Pxui.Ui.box

  val drop_targets : Pxui.Ui.t -> dragging:(Layout.path * bool) option -> geometry:Layout.geometry ->
    state:(Layout.path -> Editor_core.Panels.state) -> intent list
  (** Dock targets built after pane bodies, with PXUI hover feedback during a panel drag. *)

  val key : Layout.path -> string  (* a panel's path as text, to key its boxes *)
  val note : Pxui.Ui.t -> bounds:Layout.bounds -> string -> unit
  (* a muted line at the top of a panel body that has nothing to show *)
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

  type macro = { name : string; holes : (bool * string) array }
  (** The macro dialog's state, kept by the host: the macro's name and, for each
      literal, whether it is a hole and its name. *)

  val macro : Pxui.Ui.t -> key:string -> title:string -> literals:string array ->
    free:string list -> macro -> (macro * [ `None | `Submit ]) option
  (** A modal listing the literals (a checkbox and a hole name each; the first 12) and the
      names that always become holes, with the macro name and a Create button. [None]
      when dismissed (Escape, a press outside). *)
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
    badge : string * Rays.Color.t;  (** a kind letter on its colour *)
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
    | Rename_row | Delete_rows | Filter | Hide | Activate_row
  type t

  val create : unit -> t
  val bindings : ('scope, command) Editor_core.Command.t list
  (** Arrows, Home/End, Tab/Shift-Tab, Alt-arrows, F2, [/], [h], Enter; the host
      scopes them to its list pane. *)

  val run_command : t -> row array -> selected:int list -> command -> t * intent list
  val update : t -> Pxui.Ui.t -> Rays.Frame.t -> bounds:(int * int * int * int) ->
    ?title:string -> columns:string list -> row array -> selected:int list -> t * intent list
  (** Build the list inside [Ui.frame] and return this frame's intents;
      [title] leads the header, e.g. the level's breadcrumb. *)

  val reveal : t -> t
  (** Scroll the focused row into view on the next update. *)

  val focused : t -> int option
  val editing : t -> bool
  (** The filter or rename prompt holds the keyboard. *)
end

module Shell : sig
  val frame : Pxui.Ui.t -> Rays.Frame.t -> visible:bool ->
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
  val flow_fields : Pxui.Ui.t -> ?expanded:string list -> ?width:float ->
    ?actions:bool -> ?chips:(string * Rays.Color.t) list ->
    ?on_choice:(string -> Pxui.Ui.box -> unit) -> flow_row list -> flow_change list
  (** Responsive rows shared by Flow, scene, World, and compound interface
      inspectors. [actions=false] hides card pin and split controls. A choice named in [chips]
      wears its colour as a small square, on the closed control and in its menu. [on_choice]
      is called with the field's name and the box of each choice control, built or not
      open: a host makes it a {!Pxui.Ui.drop_target}. *)

  val fields : Pxui.Ui.t -> ?expanded:string list -> ?width:float ->
    Editor_core.Param.field_view list -> (string * Editor_core.Param.value) list
  (** One inspector row per field inside the current panel; folders become
      sections, open when their ["/"]-joined path is in [expanded]. Returns
      this frame's edits, empty when nothing changed. *)

  val record : Pxui.Ui.t -> ?expanded:string list ->
    'record Editor_core.Param.schema -> 'record ->
    ('record * Editor_core.Param.effects, string) result
  (** [fields] over a typed record, edits applied through [Param.apply_all]. *)
end
