(** Immutable value-node records. The enclosing network owns drives and
    allocates ids from its shared SOP/value id source. *)
type node = private { id : int; label : string; parameters : Value_kind.t }
type t

val node : id:int -> ?label:string -> Value_kind.kind -> (node, Diagnostic.t) result
val empty : t
val find : t -> node_id:int -> node option
val inspect : t -> node list
val add_node : node -> t -> (t, Diagnostic.t) result
val remove_nodes : int list -> t -> t
val relabel : t -> node_id:int -> string -> (t, Diagnostic.t) result
val apply_parameters :
  t -> node_id:int -> (string * Param.value) list -> (t * Param.effects, Diagnostic.t) result
val outputs : node -> (string * Port_type.t) list
