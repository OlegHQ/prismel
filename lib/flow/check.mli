(** Context-independent checking of the Flow text form. The catalog is plain
    data so the editor and the PPX can check against the same description. *)
type parameter = {
  name : string;
  label : string;
  ty : Port_type.t option;  (** [None] is a literal-only text/choice field. *)
  fields : (string * Param.kind_view * Param.value) list;
}
type slot = { name : string; required : bool; rest : bool }
(** [rest]: the last slot repeats; extras are [name_2], [name_3], ... *)

type kind = {
  qualified : string;
  aliases : string list;
  context : Context.t;
  slots : slot list;
  parameters : parameter list;
  outputs : (string * Port_type.t) list;
}

type catalog = { version : int; kinds : kind list }

type term = { node : term_node; ty : Port_type.t option }
and term_node =
  | Literal of Param.value
  | Nil
  | Vector of term list
  | Expression of Expr.t
  | Reference of string * string  (** binding, output *)
  | Call of call
and call = { kind : string; arguments : (string * term) list; bypass : bool }

type binding = { name : string; term : term; outputs : (string * Port_type.t) list }
type graph = {
  name : string;
  context : Context.t;
  bindings : binding list;
  results : term list;
}
type definition = {
  graph : graph;
  inputs : (string * Port_type.t * term option) list;
  outputs : (string * Port_type.t) list;
}
type program = { graph : graph; definitions : definition list }

val check : catalog -> string -> program option * Diagnostic.t list
(** Parse and check a file. A failed binding is poisoned, so later references
    to it do not produce cascading errors. Diagnostics include warnings and
    source positions; a program is returned only if there are no errors. *)

val catalog_of_manifest : string -> (catalog * string, Diagnostic.t) result
(** Read the generated catalog snapshot for compile-time checking, returning
    its SOP descriptor and digest. Built-in value kinds are added by [check]. *)

(** {2 Reuse by the workspace checker}
    [Flow.Workspace] calls catalog kinds through the same resolution and
    parameter validation as [%flow]. *)

val resolve_kind : catalog -> Context.t -> string -> (kind, string * string) result
(** Resolve a short or qualified kind name for a graph of the given context;
    [Error (code, message)] carries the diagnostic. Built-in [value/*] kinds
    are included. *)

val validate_parameter :
  (Diagnostic.severity -> string -> string -> unit) -> parameter -> term -> unit
(** Type, integer-literal, choice and range checks of one keyword argument;
    the callback receives severity, code and message. *)

val suggestion : string -> string list -> string
(** [" Did you mean x?"] for a close candidate, else [""]. *)

val short : string -> string
(** Unqualified kind name. *)
