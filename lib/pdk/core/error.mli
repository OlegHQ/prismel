(** Structured failures at public PDK operation and mesh boundaries. *)

type t

val make :
  ?hints:string list -> operation:string -> code:string -> string -> t
val of_string : operation:string -> code:string -> string -> t
val guard : operation:string -> code:string -> (unit -> ('a, string) result) ->
  ('a, t) result
val unguard : ('a, t) result -> ('a, string) result
(** Inverse of {!guard} for kernels composing a typed operation inside a
    string-result pipeline: re-raises cancellation, keeps the message. *)

val operation : t -> string
val code : t -> string
val message : t -> string
val hints : t -> string list
val to_string : t -> string
