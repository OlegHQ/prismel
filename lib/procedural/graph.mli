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
}

(** Deterministic input-before-consumer order. Shared nodes appear once. *)
val inspect : t -> info list
val format : t -> string
val to_dot : t -> string
