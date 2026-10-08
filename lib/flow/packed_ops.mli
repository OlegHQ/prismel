(** The operation names shared by the packed CPU/GPU emitter and the checker's
    advisory eligibility set. Adding a name requires both execution tiers to
    implement its instruction semantics. *)
type binary = Add | Sub | Mul | Div | Mod | Pow | Min | Max | Lt | Le | Gt | Ge | Eq | And | Or
type unary = Sin | Cos | Sqrt | Abs | Not

val binary : string -> binary option
val unary : string -> unary option
val noise_names : string list
val derived_names : string list
val names : string list
val supports : string -> bool
