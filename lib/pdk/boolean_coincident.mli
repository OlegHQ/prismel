(** Private ownership groups for geometrically identical refined facets. *)

type side = Left | Right
type t

val build :
  ?cancel:Cancel.t -> Boolean_constraints.t -> Boolean_coplanar.t ->
  Boolean_refinement.t -> (t, Error.t) result

val group_count : t -> int
val member_range : t -> int -> int * int
val member_side : t -> int -> side
val member_face : t -> int -> int
val member_triangle : t -> int -> int
val member_winding : t -> int -> int
(** [member_winding] is +1 or -1 relative to the stable lowest-ID member of
    its coincident group. Every contribution is retained exactly once. *)
