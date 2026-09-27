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
val sexp : t -> string
(** Both printers preserve the operation tree. *)
