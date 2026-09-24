(** Structured failures at public PDK operation and mesh boundaries. *)

type t

val make :
  ?hints:string list -> operation:string -> code:string -> string -> t
val of_string : operation:string -> code:string -> string -> t
val operation : t -> string
val code : t -> string
val message : t -> string
val hints : t -> string list
val to_string : t -> string
