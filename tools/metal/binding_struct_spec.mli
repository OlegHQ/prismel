type field =
  | Native_uint of string
  | Uint64 of string
  | Float64 of string
  | Nested of string * string

type t =
  { objc_type : string
  ; ocaml_type : string
  ; fields : field list
  }

val entries : t list
val objc_types : string list
val contains_type : string -> string -> bool
val mechanically_safe_signature : string -> bool
val validate : unit -> unit
