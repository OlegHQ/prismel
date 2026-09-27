type t = { code : string; message : string }

val error : code:string -> string -> t
val to_string : t -> string
