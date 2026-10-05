(** The graph pane's view of a checked workspace (plan W4): nodes, zones,
    rows, chips and their layout, with no drawing.  A port of the study's
    [buildView] / [buildScope] / [mkNode] / [argRows] (e1.js) and
    [layoutScope] / [nodeSize] / [place] (e2.js).

    Identity is the {!Flow.Workspace.path} of a binding, so a selection, a
    probe or a layout position survives every edit that keeps the path.  Every
    row carries the {!Flow_edit.arg_key} of the input it shows: a wire dropped
    on a row is [Flow_edit.Connect { node; key; ... }], a scrubbed number is
    [Flow_edit.Set_arg], the [Add] row's key is where the new input goes.

    Structure comes from the authored syntax (the keys and the notes live
    there); types, liveness and loop invariance come from the checker.
    A call of a node kind written in an input ({!Flow_edit.node_call}: the steps of a
    [->], a call inside a call) is a node like a bound one, placed before the node that
    holds it and wired to its row; its path ends in {!Flow_edit.nested_leaf} and it has
    no binding until it is renamed.
    ponytail: only bound loops, [let*] scopes and [fn]s are zones; an inline
    one is a chip until it is unfolded ({!Flow_edit.Unfold}), as are expressions, [ref]s
    and calls of functions and macros. *)

type path = Flow.Workspace.path

type chip =
  | No_value  (** nothing written: the row shows its default *)
  | Const  (** a number, text, flag or vector: the row's [expr] is scrubbable *)
  | Name of string
      (** a wire from a binding, loop variable or input ([a], [a.field]), or from the nested
          node written in the row (its leaf; the row's [expr] is still the call) *)
  | Inline of { glyph : string; text : string }
      (** a nested call [ƒ], loop [for] / [Σ] / [⟲], function [λ], record
          [{}] or macro call [◆], with its flat Lisp text *)

type row_kind =
  | Arg
  | Rest  (** one item of a repeating input *)
  | Add  (** the [+ input] / [+ field] row; its key is where the new one goes *)
  | Hole  (** a macro parameter *)
  | Binder  (** a macro parameter the template uses as a loop or scope name *)
  | Group_reader
  | Group_writer

type row = {
  label : string;
  key : Flow_edit.arg_key;
  ty : Flow.Ty.t option;
  expr : Flow.Syntax.t option;  (** what is written there *)
  chip : chip;
  default : string option;  (** the default a missing argument takes, as text *)
  socket : bool;  (** a wire can land here (literal-only text and choices: no) *)
  kind : row_kind;
}

type zone_kind = For | Fold | Scan | Sum | Let | Fn
type role = Var | Acc | Param | Capture

type rail_row = {
  name : string;  (** the pattern's text *)
  names : string list;  (** what it declares *)
  role : role;
  ty : Flow.Ty.t option;
  expr : Flow.Syntax.t option;  (** the collection or initial value; [None] for [Param] and [Capture] *)
  key : Flow_edit.arg_key option;  (** [Bv] into the zone form; [None] for [Param] and [Capture] *)
}

type input = { path : path; name : string; ty : Flow.Ty.t; default : Flow.Syntax.t option }

type lens = { steps : string array; error : string option; template : string }
(** A macro call and its expansion, one step at a time: [steps.(0)] is the call as
    written, [steps.(k)] the text after [k] {!Flow.Macro.expand_once} steps (at most 12);
    [error] is the diagnostic that stopped them.  [template] is the macro's definition, which
    the lens shows as one step more than [steps] ({!lens_height}'s [step] past the last). *)

type node = {
  path : path;
  name : string;
      (** the binding's text; [@result] for a synthetic result node; the leaf of a nested node *)
  binds : string list;  (** the names it declares: [name], or a pattern's names *)
  head : string;  (** [record], [number], [link], [vector], a call head, a zone keyword *)
  rows : row list;  (** empty for a zone *)
  outputs : (string * Flow.Ty.t) list;  (** record fields, or the names of a pattern *)
  ty : Flow.Ty.t;
  note : string option;
  bypass : bool;
  macro : string option;  (** the macro this node calls *)
  lens : lens option;  (** the expansion, for a macro call *)
  live : bool;  (** depends on [t] (◷) *)
  invariant : bool;  (** the same each iteration of its loop (↥) *)
  synthetic : bool;
  zone : zone option;
}

and zone = {
  kind : zone_kind;
  rail : rail_row list;
  scope : scope;
  yield_label : string;  (** collect, next, add, result, return *)
  order : string option;
      (** a loop over [sop/point_list] or [sop/piece_list] says how its elements are ordered:
          ["by index"], or ["by id"] for [:key "id"] *)
}

and scope = {
  path : path;
  inputs : input list;  (** graph inputs; empty below the root *)
  nodes : node list;  (** in authored order, the synthetic result last *)
  result : result;
}

and result =
  | Link of string
  | Node of path  (** the synthetic [@result] node *)
  | Literal of Flow.Syntax.t

val of_graph : Flow.Check.catalog -> Flow.Workspace.t -> string -> scope
(** The root scope of a graph or, for ["def:name"] or a [defn] name, of a
    definition.  Raises [Invalid_argument] when there is none. *)

val anonymous : node -> bool
(** A nested node: a call written in an input, with no binding. *)

val title : node -> string
(** What the card is called: the binding, [result], or the kind of a nested node. *)

val sources : row -> string list
(** The names a row is wired from: the nested node written in it, else every name its
    expression reads. *)

val bypassable : node -> bool
(** A call whose first input fits its result, or one already bypassed: it can carry the
    [B] flag (the checker refuses the rest with [E_BYPASS]). *)

(** A node whose positional inputs are an ordered list the user can move items in: a [list], a
    [str] or a [scene/merge] (the order of the merge is the order of the scene). *)
val reorderable : node -> bool

val find : scope -> path -> node option
(** The node at a path, searching zones. *)

val zones : scope -> node list
(** Every zone below the scope, outer first. *)

(** {2 Layout}  logical points on the 24-point row grid *)

type item = Input of input | Item of node | Return

type placed = {
  item : item;
  path : path;
  x : float;
  y : float;  (** relative to the scope's origin *)
  w : float;
  h : float;
  collapsed : bool;
  inner : layout option;  (** an expanded zone's own layout *)
}

and layout = { placed : placed list; w : float; h : float }

val layout :
  ?at:(path -> (float * float) option) -> ?collapsed:(path -> bool) ->
  ?lens:(path -> int option) -> scope -> layout
(** Columns by dependency depth, inputs first and the return last; a node
    stacks below its column's previous one.  [at] overrides a node's position
    ([Layout_by_path.at]), [collapsed] folds a zone to its card, [lens] gives the step of
    a macro call whose expansion panel is open (the card grows by {!lens_height} and
    widens to {!lens_width}).  A zone's size
    comes from its inner layout, recursively.  ponytail: no crossing
    minimisation (like [automatic_layout]). *)

val lens_width : float
val lens_height : lens -> step:int -> float
(** The expansion panel under a macro call: a row of step buttons, the printed step
    (at most 16 lines of 15 points) and the button row. *)

val place : layout -> (path * (float * float * float * float)) list
(** Absolute [(x, y, w, h)] of every placed item, zones' children included,
    outer first. *)

val rail_top : node -> float
(** Offset of a zone's first rail row from the zone's top. *)

val row_height : float
val head_height : float
val foot_height : float
val node_width : float
val rail_width : float
val yield_width : float
val strip_height : float
(** The constants of the study's card geometry (24-point rows). *)
