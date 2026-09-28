type t = private string

val valid_name : string -> bool
val reserved : string -> bool
val of_string : string -> (t, Diagnostic.t) result
val to_string : t -> string
(** Names match [[a-z][a-z0-9_]*]. Qualification belongs to kind resolution. *)
