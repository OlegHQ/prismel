type t =
  | Bound
  | Availability_gated
  | Scope_excluded
  | Unreviewed

val bound_identifiers : string list
val classify : unavailable:bool -> identifier:string -> t * string
val name : t -> string
