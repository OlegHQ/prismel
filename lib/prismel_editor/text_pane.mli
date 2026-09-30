(** The workspace text pane (plan W7): Selection, Graph and Document tabs over
    the Lisp text.  Pure state and text plus [view], which draws and returns
    intents for [Core] to apply after the frame. *)

type tab = Selection | Graph | Document
type path = Flow.Workspace.path

type shown = {
  graph : string;  (** the graph the Selection and Graph tabs read *)
  text : string;
  mark : (int * int) option;  (** byte span of the selected binding in [text] *)
  binding : (path * string) option;  (** the selected binding and its expression's text *)
  applied : string Lazy.t;  (** the whole document's text (the draft's dirty mark) *)
}

type state = {
  tab : tab;
  draft : string option;  (** the Document tab's unapplied text *)
  binding_draft : (path * string) option;
  graph_draft : (string * string) option;  (** the Graph tab's unapplied text, and its graph *)
  doc_errors : Flow.Diagnostic.t list;  (** of the last refused apply *)
  binding_errors : Flow.Diagnostic.t list;
  graph_errors : Flow.Diagnostic.t list;
  cache : ((Flow.Syntax.t list * string * path option * tab) * shown) option;
}

val initial : state

val make_shown : Flow.Syntax.t list -> string -> path option -> tab -> shown
(** [make_shown source graph selected tab]: Selection prints the selected
    binding's top-level ancestor as a [let*] over the root bindings it reads
    (a note names the count and the graph inputs used) with the binding marked;
    Graph the whole graph form; Document the workspace form. *)

val shown : state -> source:Flow.Syntax.t list -> graph:string -> selected:path option ->
  state * shown
(** {!make_shown} for the state's tab, recomputed only when the source, graph,
    selection or tab changed. *)

val line_of : string -> Flow.Diagnostic.t -> int option
(** The 1-based line of a diagnostic in the text it was checked from: its
    position, else its span. *)

val first_error : state -> Flow.Diagnostic.t option

val summary : state -> string
(** One line for crash reports: tab, draft, first error and its line. *)

type intent =
  | Tab of tab
  | Doc_draft of string
  | Doc_apply of string  (** Check & apply the whole workspace text *)
  | Doc_discard
  | Binding_draft of path * string
  | Binding_apply of path * string
  | Binding_discard
  | Graph_draft of string * string  (** the graph's name and its draft text *)
  | Graph_apply of string * string  (** Check & apply: the graph's form is replaced ({!Flow_sop.Flow_edit.Set_graph}) *)
  | Graph_discard

val view : Pxui.Ui.t -> bounds:int * int * int * int -> state -> shown -> intent list
