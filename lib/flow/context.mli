type t
(** Registry identity, comparable with [=] and safe to marshal. Register contexts
    on the initial domain before checking workspaces. *)

type descriptor = {name : string; result : Ty.t; supports_values : bool;
  label : string; color : Ty.color; group : string; catalog_prefix : string option}
val sop : t
val value : t
val draw : t
val scene : t
val world : t
val settings : t
val editor : t
val material : t

val register : descriptor -> (t, Diagnostic.t) result
(** Identical declarations are idempotent; conflicts, unknown result types,
    invalid names and duplicate catalog prefixes are refused atomically. *)

val descriptor : t -> descriptor
val all : unit -> t list
val name : t -> string
val of_string : string -> (t, Diagnostic.t) result
val result : t -> Ty.t
val of_qualified : string -> t option
val supports_values : t -> bool
