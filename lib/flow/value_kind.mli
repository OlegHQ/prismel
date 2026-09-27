(** Built-in value nodes. Literals use [Param] schemas; drives are kept by
    the enclosing network, never in these records. *)
type kind = Time | Value | Math | Combine_xyz | Separate_xyz | Remap
type t

val all : kind list
val key : kind -> string
val of_key : string -> (kind, Diagnostic.t) result
val label : kind -> string
val category : kind -> string list
val outputs : kind -> (string * Port_type.t) list

val make : kind -> t
val kind : t -> kind
val fields : t -> Param.field_view list
val field_active : t -> name:string -> bool
(** Unary math leaves [b] stored but inactive. Exposure still shows it when
    driven or explicitly pinned. *)

val parameter_key : t -> string
val apply_parameters :
  t -> (string * Param.value) list -> (t * Param.effects, Diagnostic.t) result
(** Unknown fields and invalid values are errors. An unchanged batch returns
    the original record. Vec3 storage uses its three underlying float fields. *)

val eval : time:float -> t -> ((string * Port_type.value) list, Diagnostic.t) result
