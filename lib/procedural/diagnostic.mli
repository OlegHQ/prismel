type severity = Info | Warning

type trace = {
  node_id : int;
  label : string;
  operation : string;
}

type t = {
  severity : severity;
  code : string;
  message : string;
  node : trace;
}

type error = {
  code : string;
  message : string;
  trace : trace list;
  cause : string option;
  hints : string list;
}

val make : severity -> node:trace -> code:string -> string -> t
val error : ?cause:string -> ?hints:string list -> code:string -> string -> error
val prepend_trace : trace -> error -> error
val error_to_string : error -> string
