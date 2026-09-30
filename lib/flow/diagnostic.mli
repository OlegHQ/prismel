(** Half-open byte offsets within the parsed source. *)
type span = { start : int; finish : int }
type severity = Error | Warning
type position = { line : int; col : int }

type t = { code : string; severity : severity; position : position option;
  message : string; span : span option }

val error : ?span:span -> ?position:position -> code:string -> string -> t
val warning : ?span:span -> ?position:position -> code:string -> string -> t
val to_string : t -> string

val report : file:string -> source:string -> t -> string
(** The OCaml compiler's format, so dune and editors jump to the line:
    [File "f", line N, characters A-B:] then [Error [CODE]: message] (or
    [Warning]). Lines count from 1, characters from 0 within the line; a span
    that leaves its line ends at the line's end; no span or position is line 1,
    characters 0-0. *)
