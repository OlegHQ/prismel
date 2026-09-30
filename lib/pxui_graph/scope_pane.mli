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
  | Notice of string

type direction = Left | Down | Up | Right
type command =
  | Delete  (** the hovered wired row's wire, else the selected nodes *)
  | Fold_into | Unfold | Hoist | Bypass | Wrap_repeat | Wrap_iterate | Make_fn
  | Collapse | Probe_step of int | Frame_all | Walk of direction

type stats = {
  nodes : int; zones : int; rows : int;  (** of the whole scope *)
  drawn_items : int; drawn_zones : int; drawn_rows : int;
      (** what the last frame built: only what is in view *)
}

val create : ?x:int -> ?y:int -> ?width:int -> ?height:int -> ?theme:Pxui.theme -> unit -> t
val with_bounds : x:int -> y:int -> width:int -> height:int -> t -> t
val with_visible : bool -> t -> t
val with_guide : bool -> t -> t

val with_scope :
  ?at:(path -> (float * float) option) -> ?collapsed:(path -> bool) ->
  ?probe:(path -> int) ->
  ?frames:(path -> (string * (float * float) * (float * float)) list) -> key:string ->
  Flow_sop.Projection.scope -> t -> t
(** Lay a scope out.  A new [key] (the graph's name) frames it and clears the
    selection; the same key keeps pan, zoom and selection. *)

val with_records : Flow_sop.Probe.t -> t -> t
(** What a recording evaluation saw ({!Flow_sop.Probe}): footers show the
    value at each node's probe, a sparkline across the innermost zone and the
    tags, and the selectors read their iteration counts from it.  Call it
    when the evaluation, the cooked geometry counts or the time (a live
    document) changed; a change of probe or scope is [with_scope]. *)

val selected : t -> path list
val select : path list -> t -> t
val clear_selection : t -> t
val hovered_row : t -> (path * Flow_sop.Flow_edit.arg_key) option
val stats : t -> stats
val zoom : t -> float

val bindings : ('scope, command) Editor_core.Command.t list
val run_command : t -> command -> t * change list
val update : t -> Pxui.Ui.t -> Prismel.Frame.t -> t * change list
(** Build the pane inside [Pxui.Ui.frame].  Hidden iterations are never
    built: a zone draws its body once, whatever its iteration count. *)

module Private : sig
  val box_of : t -> path -> (float * float * float * float) option
  val wires : t -> int
  val placed : t -> int
  (* previous button, track, next button, in screen points *)
  val selector : t -> path ->
    ((float * float * float * float) * (float * float * float * float) * (float * float * float * float)) option
  val output_socket : t -> path -> (float * float) option
  val row_center : t -> path -> int -> (float * float) option
end
