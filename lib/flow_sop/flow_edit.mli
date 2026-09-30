(** Every graph gesture as a pure rewrite of the workspace source (plan W3;
    a port of the study's [e1.js] / [e2.js] primitives).

    A gesture names its target by a {!type:Flow.Workspace.path}: the scope path of
    the binding, then its name ([["flower"; "ring"; "u"]], or [["g"; "@result"]]
    for a body result).  Nothing is stored beside the text, so layout keyed by
    path survives every edit that keeps the path.

    [apply] rewrites the syntax tree, prints it canonically, parses the text
    again (fresh ids and spans) and checks it with {!Flow.Workspace.check}: an
    edit that does not check is refused whole and nothing changes.  Comments
    (notes) travel with the binding name they precede, so reordering,
    rewiring, renaming, folding and wrapping keep them.

    Child indices ([sub], [Bv]) count {!Flow.Syntax.children}: for a list the
    head is child 0. *)

type path = Flow.Workspace.path

type arg_key =
  | Whole  (** the whole binding expression *)
  | Pos of int  (** positional argument *)
  | Kw of string  (** [:keyword] argument of a call *)
  | Field of string  (** field of a [{...}] record *)
  | Bv of int * int  (** child [j] of child [i], for a zone's binding vectors *)
(** The input a row of the graph edits. *)

type loop = For | Fold  (** Repeat (merge or sum) and Iterate (feed back) *)

type op =
  | Set_arg of { node : path; key : arg_key; sub : int list; value : Flow.Syntax.t }
      (** [sub] addresses a part of the argument (a vector component); a missing
          keyword or field is added *)
  | Connect of { node : path; key : arg_key; src : string; iter : bool }
      (** [src] is a name; [iter] marks a loop variable, which makes a literal
          step [n] into the product [src * n].  With [Whole] on a [@result] node it makes [src] the result of that scope. *)
  | Disconnect of { node : path; key : arg_key; fallback : Flow.Syntax.t option }
      (** a keyword or field is removed; else [fallback] (see {!default_for})
          replaces the argument, and [None] removes a positional one *)
  | Set_input_default of { form : string; input : string; value : Flow.Syntax.t }
      (** [form] is a graph name or ["def:name"] *)
  | Unfold of { node : path; key : arg_key; sub : int list }
      (** a nested call, loop or scope becomes its own binding, named by
          {!fresh_name} *)
  | Fold_into of { node : path }  (** a binding used once is inlined into its use *)
  | Wrap of { nodes : path list; loop : loop }
      (** the selected bindings (one scope, at most one result leaving)
          become a loop body; geometry is merged, numbers summed, and [Fold]
          feeds the result back into an outside input of the same type *)
  | Hoist of { node : path }  (** a loop-invariant binding moves out of its loop or scope *)
  | Rename of { node : path; to_ : string }
  | Make_local_fn of { nodes : path list }
  | Make_defn of { nodes : path list; name : string; context : string; params : (string * string) list }
      (** the selected bindings (one scope, one result leaving) become a new top-level
          [(defn name :context context [(p : type) ...] body)]; [params] types every name the
          selection reads from outside ({!defn_draft}), and a call replaces the bindings *)
  | Make_macro of { nodes : path list; name : string; holes : (int list * string) list }
      (** [holes] are child paths into the template (the binding expression, or
          [let*] over several bindings, see {!literals}) *)
  | Inline_macro of { node : path }
  | Toggle_bypass of { node : path }
  | Set_note of { node : path; text : string }
      (** a root path (a graph name) notes the form; [""] removes the note *)
  | Add_item of { node : path }
      (** a [list] literal continues a numeric step; a [str] adds a part *)
  | Move_item of { node : path; pos : int }  (** item [pos] swaps with [pos - 1] *)
  | Add_field of { node : path; name : string; value : Flow.Syntax.t }
  | Add_node of { scope : path; name : string; expr : Flow.Syntax.t }
      (** [scope] is a scope path, [["g"]] for the graph body *)
  | Delete_nodes of { nodes : path list }
  | Set_layout_ratio of { node : path; ratio : float }
      (** the binding [node] of an editor graph is a [ui/split] or [ui/split-at]; it becomes
          [ui/split-at] with this ratio (clamped to 0.1-0.9, two decimals) *)
  | Split_panel of { node : path; axis : [ `H | `V ] }
      (** the panel [node] becomes a half of a new [ui/split-at] (a fresh lisp panel beside
          it, a graph panel beside a lisp one) *)
  | Close_panel of { node : path }
      (** the split holding panel [node] becomes the other half; a panel outside a split
          does not close *)
  | Set_panel_kind of { node : path; kind : string }
      (** [outline], [graph], [list], [lisp], [inspector], [timeline] or [viewport] (over the first
          scene graph) *)
  | Set_graph of { name : string; form : Flow.Syntax.t }
      (** the whole [(graph name ...)] form, replacing the graph or appended; the scene and World
          graphs written from the editor's own objects (plan W10 write-back) *)
  | Duplicate of { nodes : path list }
      (** the bindings of one scope, copied with fresh names (the copies read each other where the
          originals did, and notes stay with the originals) *)
  | Remove_graph of { name : string }
      (** the whole graph goes (the World graph of a deleted World); the checker refuses it while a
          [(ref ...)] still reads it *)
(** ponytail: one variant and one [apply]; no command objects.  The four panel
    operations address a binding of an editor graph by its path, as every other
    op does; panels made by a loop have no binding, so they are edited on the loop. *)

val label : op -> string
(** The history label: "Repeat", "Iterate", "Unfold", "Make macro", ... *)

type macro_draft = {
  literals : (int list * Flow.Syntax.t) list;  (** the candidate holes of the template ({!literals}) *)
  free : string list;  (** outside names the template reads: they always become holes *)
  name : string;  (** a suggested macro name *)
}

val macro_draft : Flow.Syntax.t list -> path list -> (macro_draft, Flow.Diagnostic.t) result
(** What [Make_macro] over these nodes would template, for the dialog that picks its
    holes.  The errors are [Make_macro]'s (one scope, one result leaving). *)

type defn_draft = { free : string list;  (** the names the selection reads from outside *)
                    name : string  (** a suggested function name *) }

val defn_draft : Flow.Syntax.t list -> path list -> (defn_draft, Flow.Diagnostic.t) result
(** What [Make_defn] over these nodes needs typed: the outside names.  The errors are [Make_defn]'s. *)

val macro_op : macro_draft -> nodes:path list -> name:string -> (bool * string) array -> op
(** The [Make_macro] a dialog's answer means: entry [i] says whether literal [i] is a
    hole and how it is named.  Unchecked entries are copied into the template. *)

val gesture : op -> string option
(** A history merge key for a gesture that repeats while dragged (scrubbing
    an argument), [None] for everything else. *)

val apply_checked :
  Flow.Check.catalog -> Flow.Syntax.t list -> op ->
  (Flow.Syntax.t list * Flow.Workspace.t, Flow.Diagnostic.t) result
(** The rewritten source (printed and parsed again) and its check.  An op that
    has alternatives ([Wrap]) tries them in order and reports the first
    diagnostic when none checks. *)

val apply :
  Flow.Check.catalog -> Flow.Syntax.t list -> op ->
  (Flow.Syntax.t list, Flow.Diagnostic.t) result

val remap : op -> path -> path option
(** Where a layout key goes after the op: [Rename] rewrites the prefix,
    [Hoist] drops the owner segment, [Delete_nodes] drops the deleted nodes'
    keys ([None]), everything else keeps it.  ponytail: bindings that Wrap,
    Make_local_fn or Make_macro move under a new scope lose their layout key. *)

val fresh_name : Flow.Syntax.t list -> root:string -> string -> string
(** A name unused in the graph or definition [root] and not taken by an
    operator or special form; a slash prefix and other characters are
    dropped ([sop/transform] gives [transform], then [transform_2]). *)

val default_for : Flow.Ty.t -> string -> Flow.Syntax.t option
(** The value a disconnected input of this type falls back to (the study's
    [defaultFor]); [None] for types with none.  The label ["color"] makes text
    a colour. *)

val literals : Flow.Syntax.t -> (int list * Flow.Syntax.t) list
(** Number and text leaves of an expression with their child paths, the
    candidates for macro holes. *)

val duplicated : Flow.Syntax.t list -> path list -> path list
(** The paths the copies of [Duplicate { nodes }] get, in order; [[]] when it cannot apply. *)

val arg_text : Flow.Syntax.t list -> path -> arg_key -> Flow.Syntax.t option
(** The argument [key] of the binding [node], as written (what an {!Unfold} put there). *)

val arg_of : Flow.Syntax.t -> arg_key -> Flow.Syntax.t option
(** The argument [key] of an expression, as written. *)

val skip_value : int list list -> Flow.Syntax.t
(** A [:skip] value (register L16) for these tuples: bare integers when each has one. *)

val free_names : Flow.Syntax.t -> string list
(** Names a form reads and does not declare, first use first (field access
    [a.b] counts as [a]).  Projection wiring uses it. *)

val pat_names : Flow.Syntax.t -> string list
(** The names a binding pattern declares. *)

val pat_key : Flow.Syntax.t -> string
(** A pattern's text, the last segment of its path ([a], [[a b]], [{:keys [a b]}]). *)
