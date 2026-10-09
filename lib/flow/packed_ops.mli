(** The operation names shared by the packed CPU/GPU emitter and the checker's
    advisory eligibility set. Adding a name requires both execution tiers to
    implement its instruction semantics. *)
type binary = Add | Sub | Mul | Div | Mod | Pow | Min | Max | Lt | Le | Gt | Ge | Eq | And | Or
type unary = Sin | Cos | Sqrt | Abs | Not
type extension = Noise3

val register_limit : int
val supported_noise_octaves : int -> bool
val finite_float32 : float -> bool
(** Limits shared by packed compilation and GPU form qualification. *)

val scalar_width : Ty.t -> int option
(** Register widths for Float/Int/Bool and Vec2/3/4 expressions. *)

val array_width : Ty.t -> int option
(** Source widths for Array Float/Vec2/3/4 only; Int/Bool arrays are refused. *)

val binary : string -> binary option
val unary : string -> unary option
val noise_names : string list
val derived_names : string list
val names : string list
val supports : string -> bool
