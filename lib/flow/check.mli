(** Context-independent checking of the catalog. The catalog is plain
    data so the editor and the checker share one description. *)
type parameter = {
  name : string;
  label : string;
  ty : Port_type.t option;  (** [None] is a literal-only text/choice field. *)
  fields : (string * Param.kind_view * Param.value) list;
  folder : string list;  (** the folder of its (first) field *)
  primary : bool;  (** a primary field: the card shows it unset ([Flow_graph.Exposure]) *)
  unit : string option;  (** the unit suffix of a scalar field *)
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
  | Reference of string * string  (** binding, output *)

val catalog_of_manifest : string -> (catalog * string, Diagnostic.t) result
(** Read the generated catalog snapshot for compile-time checking, returning
    its descriptors and digest. *)

(** {2 Reuse by the workspace checker}
    [Flow.Workspace] calls catalog kinds through the same resolution and
    parameter validation as the sketch language. *)

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
