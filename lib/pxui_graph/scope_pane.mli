(** The graph pane of a workspace document (plan W4).  It draws one
    {!Flow_sop.Projection.scope} (nodes, zones with their rails, iteration
    selectors and yields, chips, output rows, typed sockets) and returns typed
    requests; the host reduces them.  Selection, pan, zoom and a drag in
    progress are the pane's own immutable state; positions, collapsed zones
    and probes are the host's ([~at], [~collapsed], [~probe]).  It shares the
    PXUI handle and its hit tree with every other pane. *)
type t
type path = Flow.Workspace.path

type change =
  | Syntax_edit of Flow_sop.Flow_edit.op
      (** a gesture: a wire dropped on a row is [Connect], a scrub is
          [Set_arg], deleting a wired row is [Disconnect], the [+] row is
          [Add_item] / [Add_field] / [Set_arg], the context menu and keys
          are the rest *)
  | Probe_set of { zone : path; index : int }  (** the selector moved *)
  | Zone_collapsed of { zone : path; collapsed : bool }
  | Selected of path list
  | Moved of (path * float * float) list
      (** dragged items, at their new position inside their scope *)
  | Level_set of (path * Flow_sop.Projection.level option * bool) list
      (** [o], [p] and their [⇧] forms, or a click on [+ N more]: these nodes' new level ([None]:
          back to the default, a card) and whether it is pinned (it then ignores the zoom caps).
          The host stores it by path ([Layout_by_path.level] / [pinned]), one history entry. *)
  | Copy_requested of path list
      (** Command-C / Command-X: the host puts these bindings' text on the clipboard (a cut
          also deletes them) *)
  | Paste_requested  (** Command-V: the host adds the clipboard's bindings to the selected scope *)
  | Menu_requested of float * float
      (** a right-click on empty canvas: the host opens its add menu at this point *)
  | Macro_requested of path list
  | Defn_requested of path list
      (** [m]: the host opens its make-macro dialog over these nodes *)
  | Frames_set of { scope : path; frames : (string * (float * float) * (float * float)) list }
      (** the titled frames of one scope after a gesture: Shift-G makes one around the selection,
          its corner resizes it, a double-click on its title renames it, its cross deletes it
          (layout data, never printed) *)
  | Display_set of path
      (** [v]: show this geometry node in the viewport instead of the graph's result (the node
          already shown goes back to the result) *)
  | Activated of path
      (** a double-click on the body of a node (its title renames): the host follows what it
          references *)
  | Drop_over of { path : path; kind : string; value : string }
      (** a carried payload ({!Pxui.Ui.carry}) is held over this node, or over the empty canvas
          (the path [[graph]], one segment): the host decides whether it would take it *)
  | Dropped of { path : path; kind : string; value : string }
      (** the payload was released there; the pane never edits, the host turns it into a gesture *)
  | Notice of string

type direction = Left | Down | Up | Right
type command =
  | Delete  (** the hovered wired row's wire, else the selected nodes *)
  | Fold_into | Unfold | Hoist | Bypass | Wrap_repeat | Wrap_iterate | Make_fn | Make_macro | Make_defn
  | Collapse | Probe_step of int | Frame_all | Walk of direction
  | Edit_name
      (** F2, or a double-click on a title: a text field over the selected node's name
          ([Rename]) or, on a graph input, over its default ([Set_input_default]) *)
  | Item_up | Item_down  (** Alt-Up / Alt-Down on the hovered list row: [Move_item]; each row has an [↑] button *)
  | Make_frame  (** Shift-G *)
  | Duplicate  (** Command-D: copy the selected nodes with fresh names ({!Flow_sop.Flow_edit.Duplicate}) *)
  | Display  (** [v]: {!Display_set} for the selected geometry node *)
  | Copy | Cut | Paste  (** Command-C / X / V: {!Copy_requested} (a cut deletes too), {!Paste_requested} *)
  | Frame_selection  (** [⇧F]: pan and zoom to the selected nodes (all of them with none selected) *)
  | Open_level  (** [o]: the selected nodes one level more detailed, pinned *)
  | Point_level  (** [p]: the selected nodes to points, or back to the level they had *)
  | Open_all  (** [⇧O]: every node to the default level *)
  | Point_all  (** [⇧P]: every node to a point, or every node back *)
  | Show_hints
      (** [f]: with one node selected, a letter chip on every node it can connect to (a node with
          several fitting inputs asks for a second letter); a complete label is a
          [Syntax_edit (Connect ...)], Escape, Backspace on an empty label or a click cancels.
          {!editing} is true meanwhile, so the host keeps its keys out. *)

type stats = {
  nodes : int; zones : int; rows : int;  (** of the whole scope *)
  drawn_items : int; drawn_zones : int; drawn_rows : int;
      (** what the last frame built: only what is in view *)
}

val create : ?x:int -> ?y:int -> ?width:int -> ?height:int -> ?theme:Pxui.theme -> unit -> t
val with_bounds : x:int -> y:int -> width:int -> height:int -> t -> t
val with_visible : bool -> t -> t
val with_guide : bool -> t -> t

val with_theme : Pxui.theme -> t -> t
(** The theme the pane paints with: a window's canvas is the sheet, a docked one the ground. *)

val with_failed : (path * string) list -> t -> t
(** The nodes a cook or the checker refused, each with the diagnostic's code: the card wears the
    sheet's failed state (invalid edge, square and name, the code in the kind's place). *)

val with_carry : lit:(path * string) list -> hot:(path * bool) option -> t -> t
(** While a payload is carried: the nodes it can be put on, each with its letter (the key
    route), and the node or canvas under the pointer with whether it takes the payload. *)

val with_scope :
  ?at:(path -> (float * float) option) ->
  ?level:(path -> (Flow_sop.Projection.level * bool) option) -> ?collapsed:(path -> bool) ->
  ?probe:(path -> int) ->
  ?frames:(path -> (string * (float * float) * (float * float)) list) -> ?display:path ->
  ?wires:[ `Rect | `Straight ] -> ?layouts:string list ->
  key:string ->
  Flow_sop.Projection.scope -> t -> t
(** Lay a scope out.  A new [key] (the graph's name) frames it and clears the
    selection; the same key keeps pan, zoom and selection.  [layouts] are the names of a
    [ui/switch]'s layouts: its rows read as them, the active wire is solid and accented, the
    others dashed grey, and a click on a row is [Set_layout] on the graph [key]. *)

val with_records : Flow_sop.Probe.t -> t -> t
(** What a recording evaluation saw ({!Flow_sop.Probe}): footers show the
    value at each node's probe, a sparkline across the innermost zone and the
    tags, and the selectors read their iteration counts from it.  Call it
    when the evaluation, the cooked geometry counts or the time (a live
    document) changed; a change of probe or scope is [with_scope]. *)

val macro_step : t -> path -> int option
(** The step shown by the open expansion panel of a macro call ([0] is the call as
    written); [None] while the panel is closed.  The panel is opened by the toggle at the
    right of the card's title and its step buttons choose the step (view state); its
    "Replace call with expansion" button is [Syntax_edit (Inline_macro ...)]. *)

val editing : t -> bool
(** A text field (a name, an input default, a frame title) is open, or letter hints are up: the
    host keeps its keys out. *)

val selected : t -> path list
val selected_wire : t -> (path * Flow_sop.Flow_edit.arg_key) option
val select : path list -> t -> t
val clear_selection : t -> t
val stats : t -> stats
val zoom : t -> float
val wires : t -> [ `Rect | `Straight ]
(** [`Straight] (the default, the sheet's wires): one segment port to port, bent clear of any
    card it would cross; [`Rect] is the old orthogonal routing, for [:wires "rect"]. *)

val with_wires : [ `Rect | `Straight ] -> t -> t

val scope_point : t -> scope:path -> float * float -> (float * float) option
(** A screen point as a position inside [scope] (a scope path of the shown graph), snapped to the
    24-point dot lattice: where a node added from a menu opened there is placed ([Moved]). *)

val bindings : ('scope, command) Editor_core.Command.t list
val run_command : t -> command -> t * change list
val update : t -> Pxui.Ui.t -> Rays.Frame.t -> t * change list
(** Build the pane inside [Pxui.Ui.frame].  Hidden iterations are never
    built: a zone draws its body once, whatever its iteration count. *)

module Private : sig
  val highlighted_connections : t -> ((float * float) * (float * float)) list
  val box_of : t -> path -> (float * float * float * float) option
  (* previous button, track, next button, in screen points *)
  val selector : t -> path ->
    ((float * float * float * float) * (float * float * float * float) * (float * float * float * float)) option
  val output_socket : t -> path -> (float * float) option
  val row_center : t -> path -> int -> (float * float) option
  val lens_toggle : t -> path -> (float * float) option
  (* centres, in screen points, of the panel's parts *)
  val lens_step_button : t -> path -> int -> (float * float) option
  val lens_replace : t -> path -> (float * float) option
  val wire_count : t -> int
  val wire_points : t -> int -> (float * float) list
  val wire_target : t -> int -> (path * Flow_sop.Flow_edit.arg_key) option
  val wire_midpoint : t -> int -> (float * float) option
end
