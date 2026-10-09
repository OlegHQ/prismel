(** Immutable built-in operator declarations. Checker, evaluator and editor share these records. *)
type signature = {
  pos : (string * Ty.t) list; opt : (string * Ty.t) list;
  rest : (string * Ty.t) option; kw : (string * Ty.t) list;
}
type shape = Scalar | Struct of { splice : bool }
type arithmetic = { apply : 'f 'r. ('f, 'r) Value.t -> ('f, 'r) Value.t -> ('f, 'r) Value.t }
type packed_kind = Binary of Packed_ops.binary | Unary of Packed_ops.unary
  | Noise3 | Length | Exact | Frame | Constant_only
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
  packed_extension : Packed_ops.extension option;
  (** Asserts the intrinsic's semantics, not just its signature. Clear this
      capability when copying a declaration and changing its behavior. *)
}
val all : t list
val find : ?extra:t list -> string -> Context.t -> t option
(** Exact head, then bare value head, then a head qualified by the given context. *)

val of_context : ?extra:t list -> Context.t -> t list
(** Context-specific operators followed by the value operators, in declaration order. *)

val arith : string -> arithmetic option

val packed_kind : t -> packed_kind option
(** Canonical scalar built-ins or a validated explicit intrinsic capability.
    [Constant_only] permits existing constant folding without promising a
    dynamic register instruction. *)

val is_display_kind : string -> bool
(** Drawing and UI consumers may display approximate values. *)

val validate : t list -> Diagnostic.t option
(** Check an immutable extension list; declarations cannot shadow built-ins. *)

val max_iterations : int
