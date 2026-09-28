(** Context-independent checking of the Flow text form. The catalog is plain
    data so the editor and the PPX can check against the same description. *)
type parameter = {
  name : string;
  label : string;
  ty : Port_type.t option;  (** [None] is a literal-only text/choice field. *)
  fields : (string * Param.kind_view * Param.value) list;
}
type slot = { name : string; required : bool }

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
