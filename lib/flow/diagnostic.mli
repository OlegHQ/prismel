(** Half-open byte offsets within the parsed source. *)
type span = { start : int; finish : int }
type severity = Error | Warning
type position = { line : int; col : int }

type t = { code : string; severity : severity; position : position option;
  message : string; span : span option }

val error : ?span:span -> ?position:position -> code:string -> string -> t
val warning : ?span:span -> ?position:position -> code:string -> string -> t
val to_string : t -> string
