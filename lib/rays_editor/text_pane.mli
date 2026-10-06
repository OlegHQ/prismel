(** The workspace text pane (plan W7): Selection, Graph and Document tabs over
    the Lisp text.  Pure state and text plus [view], which draws and returns
    intents for [Core] to apply after the frame. *)

type tab = Selection | Graph | Document
type path = Flow.Workspace.path

type shown = {
  graph : string;  (** the graph the Selection and Graph tabs read *)
  text : string;
  mark : (int * int) option;  (** byte span of the selected binding in [text] *)
  key : path;  (** what the Selection tab shows and its apply writes: the selected binding's
                   path, else [[graph]] *)
  applied : string Lazy.t;  (** the whole document's text (the draft's dirty mark) *)
  body : (Flow.Syntax.t * (int * Flow.Diagnostic.span) list) option;
      (** the Graph tab's graph body and the spans of [text]: what the caret is looked up in *)
}

type state = {
  tab : tab;
  draft : string option;  (** the Document tab's unapplied text *)
  binding_draft : (path * string) option;  (** the Selection tab's unapplied text, keyed by [shown.key] *)
  graph_draft : (string * string) option;  (** the Graph tab's unapplied text, and its graph *)
  doc_base : Editor_document.Workspace_doc.t option; (** base document of the draft *)
  binding_base : Editor_document.Workspace_doc.t option;
  graph_base : Editor_document.Workspace_doc.t option;
  doc_errors : Flow.Diagnostic.t list;  (** of the last refused apply *)
  binding_errors : Flow.Diagnostic.t list;
  graph_errors : Flow.Diagnostic.t list;
  wrap : bool;  (** long lines continue on the next row (the right-click menu toggles it) *)
  parinfer : bool;  (** the closing brackets follow indentation, {!Lisp_text.parinfer_text} (the
                        right-click menu toggles it; on by default) *)
  menu : (float * float) option;  (** the right-click menu while it is open *)
  picker : (int * int * bool) option;  (** the colour literal being edited: byte range, edited yet *)
  cache : ((Flow.Syntax.t list * Editor_document.Workspace_doc.t option * string * path option * tab) * shown) option;
}

val initial : state

val binding : Flow.Syntax.t list -> path -> (Flow.Syntax.t option * Flow.Syntax.t) option
(** The binding a path names in the source: its pattern (none for a [@result]) and expression. *)

val selection_form : Flow.Syntax.t list -> path -> Flow.Syntax.t ->
  (Flow.Syntax.t, Flow.Diagnostic.t) result
(** Patch named root bindings into one candidate graph. Omitted bindings stay;
    duplicate names and changes to the shown result are refused. Check the

val graph_op : Flow.Syntax.t list -> graph:string -> ?selection:path -> string ->
  (Flow_sop.Flow_edit.op, Flow.Diagnostic.t) result
(** The [Set_graph] of the graph form a Graph tab holds, or (with [selection], the shown binding's
    path) of the Selection closure patched into the graph; the error of text that is neither. *)
    complete returned graph once before installing it. *)

val graph_op : Flow.Syntax.t list -> graph:string -> ?selection:path -> string ->
  (Flow_sop.Flow_edit.op, Flow.Diagnostic.t) result
(** The [Set_graph] of the graph form a Graph tab holds, or (with [selection], the shown binding's
    path) of the Selection closure patched into the graph; the error of text that is neither. *)

val paste_ops : Flow.Syntax.t list -> graph:string -> scope:path -> string ->
  (Flow_sop.Flow_edit.op list, string) result
(** Pasted text as [Add_node]s of [scope]: [name expr] pairs, or bare expressions named by their
    head.  Names pair by position and are made free of the graph's and of each other; a pasted
    binding that reads an earlier pasted one reads its new name (all renames at once). *)

val merge3 : base:string -> mine:string -> theirs:string -> string option
(** A draft ([mine]) begun from [base], against the text the document has now ([theirs]): the
    three merged on the syntax tree, graphs and [let*] bindings paired by name.  [None] when both
    changed the same value or the draft does not read. *)

val make_shown : Flow.Syntax.t list -> string -> path option -> tab -> shown
(** [make_shown source graph selected tab]: Selection prints the selected
    binding's top-level ancestor as a [let*] over the root bindings it reads
    (a note names the count and the graph inputs used) with the binding marked;
    Graph the whole graph form; Document the workspace form. *)

val shown : ?workspace:Editor_document.Workspace_doc.t -> state -> source:Flow.Syntax.t list -> graph:string -> selected:path option ->
  state * shown
(** {!make_shown} for the state's tab, cached by source, optional workspace, graph,
    selection and tab. A workspace includes saved layout and settings in the Document tab. *)

val line_of : string -> Flow.Diagnostic.t -> int option
(** The 1-based line of a diagnostic in the text it was checked from: its
    position, else its span. *)

val binding_at : shown -> int -> path option
(** The path of the innermost binding of the Graph tab whose text holds the byte. *)

val cameras : Flow.Syntax.t list -> string -> string list
(** The bindings of a scene graph that are [scene/camera] calls. *)

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
      (** Check & apply of Selection: patch the shown closure's named bindings
          into one candidate graph, preserving omitted bindings and refusing
          changed results or duplicate names. Check and lower once via
          {!Flow_sop.Flow_edit.Set_graph}. *)
  | Binding_discard
  | Graph_draft of string * string  (** the graph's name and its draft text *)
  | Graph_apply of string * string  (** Check & apply: the graph's form is replaced ({!Flow_sop.Flow_edit.Set_graph}) *)
  | Graph_discard
  | Menu of (float * float) option  (** the right-click menu opened here, or closed *)
  | Toggle_wrap
  | Doc_scrub of string * bool
      (** the Document text while a number in it is dragged ([true] on the frame the drag ends):
          applied live, one history entry *)
  | Graph_scrub of string * string * bool
  | Binding_scrub of path * string * bool
  | Toggle_parinfer
  | Picker of (int * int * bool) option
      (** the colour literal (byte range with its quotes) whose control is open, and whether an edit was made *)
  | Open_graph of string  (** Command-click on a [(ref name)]: show that graph (the back stack remembers this one) *)
  | Select_binding of path  (** the caret moved into this binding of the Graph tab: select its node *)
  | Carry_over of int * bool
      (** a payload is held over the text at this byte of the shown text; [true] on the frame it is released *)

val tabs_width : Pxui.Ui.t -> width:int -> state -> shown -> float
(** The room the Selection / Graph / Document tabs of {!view} take in the header of a panel
    [width] wide. *)

val view : Pxui.Ui.t -> bounds:int * int * int * int -> tabs_right:float option -> vocab:Lisp_text.vocab -> names:Lisp_text.names -> state -> shown -> intent list
