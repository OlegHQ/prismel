(** The v4 document: a checked workspace, its layout keyed by path and the
    sketch settings (plan W3).  UI-free.  The source text is the authored
    truth; [checked] is derived from it and every edit re-checks atomically.

    The persisted text is the workspace form itself followed by optional
    [(layout ...)] ({!Layout_by_path}) and [(settings :name value ...)] forms
    (only settings that differ from their default). A [.rays] sketch can
    include those trailing forms as well. *)

type t = {
  source : Flow.Syntax.t list;  (** the one [(workspace ...)] form *)
  checked : Flow.Workspace.t;
  layout : Layout_by_path.t;
  settings : Settings.t;
  extra : Flow.Syntax.t list;
      (** the other root forms as they were written, for {!to_text}: a [(view ...)] is kept
          verbatim; [layout] and [settings] are kept for the comments above and inside them *)
}

val name : t -> string

val editor_graph : t -> Flow.Workspace.graph option
(** The selected named editor layout, or the first editor graph when none is selected. *)

val of_text :
  ?settings:Settings.t -> ?layout:Layout_by_path.t -> Flow.Check.catalog -> string -> (t, Flow.Diagnostic.t list) result
(** Parse and check. Absent settings and layout forms retain the supplied values.
    An explicit settings form starts from its schema defaults; an explicit empty layout clears it.
    Errors are the checker's diagnostics, a parse error, or a layout or
    settings form that does not read ([E_LAYOUT], [E_SETTINGS], with the form's span). Unknown or
    duplicate document forms give [E_DOCUMENT_FORM].  A layout entry whose path is not in the
    checked workspace is dropped, and so is a selected editor layout that names no editor graph. *)

val check_text :
  ?settings:Settings.t -> ?layout:Layout_by_path.t -> Flow.Check.catalog -> string ->
  (t * Flow.Diagnostic.t list, Flow.Diagnostic.t list) result
(** {!of_text} with the checker's warnings. *)

val to_text : t -> string
(** Canonical text; read with the same settings schema at its defaults to
    recover the complete saved document.  Comments between and after the root forms and a
    [(view ...)] form are kept. *)

val edit : Flow.Check.catalog -> t -> Flow_sop.Flow_edit.op -> (t, Flow.Diagnostic.t) result
(** One gesture, atomically: the source is rewritten and re-checked, layout
    keys follow {!Flow_sop.Flow_edit.remap} and are pruned as in {!of_text}, and on an error
    nothing changes. *)
