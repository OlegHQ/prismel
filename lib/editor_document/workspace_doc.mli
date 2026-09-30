(** The v4 document: a checked workspace, its layout keyed by path and the
    sketch settings (plan W3).  UI-free.  The source text is the authored
    truth; [checked] is derived from it and every edit re-checks atomically.

    The persisted text is the workspace form itself followed by optional
    [(layout ...)] ({!Layout_by_path}) and [(settings :name value ...)] forms
    (only settings that differ from their default).  A [.plisp] sketch is the
    same text without the trailing forms. *)

type t = {
  source : Flow.Syntax.t list;  (** the one [(workspace ...)] form *)
  checked : Flow.Workspace.t;
  layout : Layout_by_path.t;
  settings : Settings.t;
}

val name : t -> string

val of_text :
  ?settings:Settings.t -> Flow.Check.catalog -> string -> (t, Flow.Diagnostic.t list) result
(** Parse and check.  [settings] is the sketch's value the saved fields apply
    to.  Errors are the checker's diagnostics, a parse error, or a layout or
    settings form that does not read ([E_LAYOUT], [E_SETTINGS]). *)

val to_text : t -> string
(** Canonical text; [of_text] of it gives an equal document. *)

val edit : Flow.Check.catalog -> t -> Flow_sop.Flow_edit.op -> (t, Flow.Diagnostic.t) result
(** One gesture, atomically: the source is rewritten and re-checked, layout
    keys follow {!Flow_sop.Flow_edit.remap}, and on an error nothing changes. *)
