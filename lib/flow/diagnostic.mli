type span = { start : int; finish : int }
(** Half-open byte offsets within the parsed source. *)

type t = { code : string; message : string; span : span option }

val error : ?span:span -> code:string -> string -> t
val to_string : t -> string
