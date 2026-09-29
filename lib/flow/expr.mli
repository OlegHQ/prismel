type op = Add | Sub | Mul | Div | Pow | Min | Max | Sin | Cos | Abs | Floor | Sqrt
type t = private Num of float | Time | Op of op * t list

val operators : (string * op) list
val arity : op -> int
val num : float -> (t, Diagnostic.t) result
val time : t
val op : op -> t list -> (t, Diagnostic.t) result
val apply : op -> float list -> (float, Diagnostic.t) result
val eval : time:float -> t -> (float, Diagnostic.t) result
val depends_on_time : t -> bool

val parse_infix : string -> (t, Diagnostic.t) result
val parse_sexp : string -> (t, Diagnostic.t) result
val parse : string -> (t, Diagnostic.t) result
(** Accept infix, or an s-expression beginning with [(]. Errors carry source
    byte spans; unary minus binds tighter than right-associative [^]. *)

val infix : t -> string
val sexp : ?precision:int -> t -> string
(** Both printers preserve the operation tree. [sexp] defaults to 17
    significant digits for exact numeric round trips. *)

val sexp_number : ?precision:int -> float -> string
(** Finite decimal spelling accepted by the Flow S-expression reader,
    including values normally formatted with an exponent. Defaults to 17
    significant digits; use 6 for a compact display. *)
