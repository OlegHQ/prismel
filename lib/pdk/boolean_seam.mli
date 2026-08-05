(** Private exact seam and coincident-surface product from a Boolean complex. *)

type kind = Left_self | Between | Right_self
type t

val build :
  ?cancel:Cancel.t -> ?grain:int -> ?parallel_cutoff:int ->
  Boolean_complex.t -> (t, Error.t) result
(** O(V + E + F + I) time and O(V + E + F) auxiliary/output storage, where
    [I] is complex edge/facet incidence. Classification uses stable disjoint
    ranges above [parallel_cutoff]; chaining remains deterministic and linear. *)

val curves : t -> Geometry.t
(** Deterministically chained open/closed polylines. Branch vertices terminate
    a path; every selected complex edge appears exactly once. *)

val coincident : t -> Geometry.t
(** Exact coincident-area facets, emitted once with their complex orientation. *)

val curve_kind : t -> int -> kind
val curve_edge_range : t -> int -> int * int
val curve_edge : t -> int -> int
(** Source complex-edge ancestry for each curve, stored as packed CSR. *)

module Private : sig
  val complex : t -> Boolean_complex.t
  val is_seam_edge : t -> int -> bool
  val verify_curves :
    ?cancel:Cancel.t -> grain:int -> Geometry.t -> (unit, Error.t) result
  (** Exact post-rounding self-intersection verification over packed curve
      segments. Intended for focused malformed-output regressions. *)
end
