type t = Node.t

type info = {
  id : int;
  label : string;
  operation : string;
  version : int;
  parameters : string;
  cook_mode : Node.cook_mode;
  dependencies : Context.Dependencies.t;
  input_ids : int list;
  has_parameters : bool;
}

(** Deterministic input-before-consumer order. Shared nodes appear once. *)
val inspect : t -> info list
val find : t -> node_id:int -> Node.t option

(** Union of context facts consumed anywhere in the reachable DAG. Sketch
    runtimes use this to schedule external-effect recooks. *)
val dependencies : t -> Context.Dependencies.t

val format : t -> string
val to_dot : t -> string
