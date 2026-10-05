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
    | Split of { axis : axis; size : Editor_core.Panels.size; a : t; b : t }
    | Tile of t list
    | Float of t
  type path = int list
  type bounds = int * int * int * int

  val default : t

  val header_height : int
  (** One unit, 24 points: a panel header, the status strip, a docked timeline. *)

  val header_margin : int
  (** The 4 points above a panel's header row (none on a collapsed docked pane). *)

  type leaf = { path : path; panel : panel; frame : bounds; header : bounds; body : bounds; floating : bool }
  (** One panel: its [frame], the 24-point [header] row under a 4-point margin, and the body
      below it.  A docked timeline under 90 points has no header: it is its strip. [floating] covers both authored
      [Float] trees and panels undocked through saved window state. *)

  type splitter = { node : path option; axis : axis; size : Editor_core.Panels.size; bounds : bounds;
                    start : int; span : int }
  (** A gutter.  [node] is the split it resizes (none for a tile's fixed gutters) and [size]
      what that split is sized by; [start] and [span] are the extent, along [axis], of the
      columns that split divides, so a pointer position maps to a ratio or to the points of
      the fixed side. *)

  val sides : splitter -> int * int
  (** The points its split gives each side now, along the axis. *)

  val resized : splitter -> [ `Ratio | `First | `Second ] -> Editor_core.Panels.size
  (** The split sized another way, keeping what it shows: by ratio, or with one side fixed. *)

  type geometry = { leaves : leaf list; splitters : splitter list; status_at : bounds;
                    timeline_at : bounds }
  (** Leaves in tree order, floats last (drawn over the rest). *)

  val geometry : ?state:(path -> Editor_core.Panels.state) -> ?hidden:panel list -> t -> Rays.Frame.t -> geometry
  (** [hidden] (default the timeline) panels vanish; a hidden viewport and a collapsed
      panel keep a strip with the expand button (the 24-point header in a stack, a 24-point
      column in a row).  A split with a fixed side gives that side its points and the other
      the rest; when both do not fit, the other side keeps its minimum first and the fixed
      side shrinks, never below one point.  A [Timeline] leaf in a stack is 24 points; a tree
      without one has a 25-point strip under it (a hairline and the bar).  The 25-point status
      strip (a hairline and a 24-point bar) spans the frame below both.  Every point of the frame
      is covered exactly once, floats aside; a leaf's [frame] is its margin, header and body. *)

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

(** Kit rev 3 pieces every bar shares. *)
module Kit : sig
  val cap_width : Pxui.Ui.t -> string -> float
  (** The width of a label ({!Pxui.Ui.Paint.cap}), measurable before painting. *)

  val text_y : Pxui.Ui.t -> float -> float -> float
  (** [text_y ui y h]: where kit text sits in a bar at [y] of height [h]. *)

  val cap_y : Pxui.Ui.t -> float -> float -> float
  val cap_size : Pxui.Ui.t -> int

  val button_width : Pxui.Ui.t -> ?hint:string -> ?icon:bool -> string -> float

  val button : Pxui.Ui.t -> key:string -> at:float * float -> w:float -> ?h:float -> ?enabled:bool ->
    ?active:bool -> ?primary:bool -> ?centered:bool -> ?hint:string -> ?icon:[ `Play | `Stop ] -> string -> bool
  (** A text button and, in ink-3, its key: hover and pressed fills, the control fill while
      [active]; [primary] is the one outlined button of a panel; [centered] centres a label in a
      button wider than its text (an icon button).  True on a click. *)

  val switch : Pxui.Ui.t -> key:string -> at:float * float -> bool -> bool
  (** The kit's 28 x 14 switch, on or off; true on a click. *)

  val segments : Pxui.Ui.t -> key:string -> right:float -> y:float -> ?h:float -> string list -> int ->
    int option * float
  (** Text tabs laid out leftwards from [right], the one in use underlined: the tab clicked
      and where the row starts. *)
end

module Chrome : sig
  type intent =
    | Resize of { node : Layout.path; size : Editor_core.Panels.size }
        (** a splitter is being dragged ({!splitters}): a ratio, or the whole points of the fixed side *)
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

  val update : ?state:(Layout.path -> Editor_core.Panels.state) -> ?hidden:Layout.panel list -> ?title:(Layout.leaf -> string) ->
    ?focus:Layout.path -> Layout.t -> Pxui.Ui.t -> Rays.Frame.t -> intent list
  (** A [title] is ["Kind<TAB>a / b"]: the kind is the header's label, the rest its breadcrumb
      (the last part in ink).  The header of the [focus] leaf wears the accent square.  A docked
      header ends in its collapse chevron, a window's in dock and close.
      Panel backgrounds, the drawn gutters, headers with their collapse button and
      right-click menu (split, close, dock, retype, and the size of the split that holds the
      panel: a [Resize] then [Settled], as the gutter's menu).  Pure: the host applies the intents. *)

  val tools_start : Pxui.Ui.t -> focused:bool -> floating:bool -> collapsed:bool -> string -> float
  (** Where the tools of a header begin, from its left edge: after the title as {!update} lays
      it out, an 8-point gap, the 1 x 12 rule between two 4-point margins and an 8-point gap. *)

  val splitters : ?state:(Layout.path -> Editor_core.Panels.state) -> ?hidden:Layout.panel list -> Layout.t -> Pxui.Ui.t -> Rays.Frame.t ->
    intent list
  (** The gutters' drag targets, wider than they are drawn ([Resize], [Settled]), and their
      right-click menu: By ratio, Fix first side, Fix second side (a [Resize] of the size the
      split shows, then [Settled]).  Call it
      after the panes' boxes so a gutter is not shadowed by its neighbours' hit areas. *)

  (* A pane's PXUI hit ancestor; children keep screen-space coordinates. *)
  val pane_root : Pxui.Ui.t -> Rays.Frame.t -> bounds:Layout.bounds ->
    string -> Pxui.Ui.box

  val drop_targets : Pxui.Ui.t -> dragging:(Layout.path * bool) option -> geometry:Layout.geometry ->
    state:(Layout.path -> Editor_core.Panels.state) -> intent list
  (** Dock targets built after pane bodies, with PXUI hover feedback during a panel drag. *)

  val key : Layout.path -> string  (* a panel's path as text, to key its boxes *)
  val note : Pxui.Ui.t -> bounds:Layout.bounds -> string -> unit
  (* a panel body that has nothing to show: a crossed box and the reason as a label *)
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
  type state = [ `Ok | `Busy | `Error ]
  (** What the dot after the file says: checked and cooked, cooking, refused. *)

  val guide : Pxui.Ui.t -> bounds:Layout.bounds -> ?file:string -> ?state:state -> ?layout:string ->
    ?text:string -> ?fps:int -> ?notes:string list -> ?accent:bool -> ?extra:(string * string) list ->
    ?kind:string -> ?selection:string -> context:Editor_core.Guide_context.t ->
    ('scope, 'action) Editor_core.Command.t list -> bool
  (** The strip of the workspace sheet: a hairline over a 24-point bar of the file, its state dot
      and status line (a quarter of the strip at most), a rule, the focused pane's [kind] and the
      [selection] as labels (a context that is not a node's names itself in place of the
      selection; a List or Text context shows the selection given), each applicable key in ink-3
      before what it does in ink-2 ([extra] pairs follow the keymap's, for gestures that are no
      command), then the [notes] (labels such as "3 graphs"), the layout in use and the frame rate
      at the right; [accent] draws the kind in the accent (a panel being moved); true when the
      "toggle guide" pair is clicked. *)

  val hud : Pxui.Ui.t -> bounds:Layout.bounds -> text:string -> unit
  (** Noninteractive key feedback in the pane's bottom corner. *)

  val draw : Pxui.Ui.t -> bounds:(int * int * int * int) -> ?file:string -> ?state:state ->
    ?layout:string -> ?notes:string list -> ?accent:bool -> ?kind:string -> ?selection:string ->
    text:string -> fps:int option -> unit -> unit
  (** The status strip without the keys: the file, its state, the whole status line, the
      layout in use and the frame rate. *)
end

module Timeline_bar : sig
  type intent = Pause_toggle | Stop_playback | Reset_playback
    | Seek_playback of int64
    | Set_end of int  (** the last frame, typed in a tall timeline's End field *)

  val draw : Pxui.Ui.t -> bounds:(int * int * int * int) -> ?edge:bool -> playing:bool ->
    frame:int64 -> time:float -> max_frame:int -> unit -> intent list
  (** Draw timeline controls and return playback requests.  The frame is a field: a click
      opens it, Enter commits (clamped to 0 and [max_frame]), Escape cancels.  A body under 56
      points is the one 24-point bar of the workspace sheet (Play, Stop, F, the frame, the time,
      the ruler); a taller panel adds Reset, Frame, Time, End and a numbered ruler under a hairline.
      [edge] puts a line-2 hairline on the strip's top row (a strip no gutter lies over). *)
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

  val summary : t -> string
  (** One line for crash reports and tests: the focus row, the folds, the filter. *)

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
    ?actions:bool -> ?pins:bool -> ?chips:(string * Rays.Color.t) list ->
    ?on_choice:(string -> Pxui.Ui.box -> unit) -> flow_row list -> flow_change list
  (** Responsive rows shared by Flow, scene, World, and compound interface
      inspectors, laid out as the kit's inspector sheet. [actions=false] hides card pin and split
      controls; [pins] draws each row's pin dot ([shown]: filled when the row is on its card, a
      ring when not), a click on it being [Pinned] under [actions]. A drive's cross shows on the
      hovered row. A choice named in [chips]
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
