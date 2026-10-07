(** Immutable built-in operator declarations. Checker, evaluator and editor share these records. *)
type signature = {
  pos : (string * Ty.t) list; opt : (string * Ty.t) list;
  rest : (string * Ty.t) option; kw : (string * Ty.t) list;
}
type shape = Scalar | Struct of { splice : bool }
type arithmetic = { apply : 'f 'r. ('f, 'r) Value.t -> ('f, 'r) Value.t -> ('f, 'r) Value.t }
type t = {
  name : string; ctx : Context.t; signature : signature;
  out : Ty.t list -> Ty.t; any_num : bool;
  choices : (string * string list) list; shape : shape;
  live : bool;
  check : 'f 'r. (string * ('f, 'r) Value.t) list -> unit;
  body : 'f 'r. live:Frame_input.t -> node:(string -> (string * ('f, 'r) Value.t) list -> ('f, 'r) Value.t) ->
    (string * ('f, 'r) Value.t) list -> ('f, 'r) Value.t;
  category : string;
  arithmetic : arithmetic option;
}
val all : t list
val find : ?extra:t list -> string -> Context.t -> t option
(** Exact head, then bare value head, then a head qualified by the given context. *)

val of_context : ?extra:t list -> Context.t -> t list
(** Context-specific operators followed by the value operators, in declaration order. *)

val arith : string -> arithmetic option

val validate : t list -> Diagnostic.t option
(** Check an immutable extension list; declarations cannot shadow built-ins. *)

val max_iterations : int
