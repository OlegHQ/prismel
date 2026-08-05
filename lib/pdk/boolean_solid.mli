(** Private build-once exact solid Boolean arrangement. *)

type t
type treatment = Solid | Surface
type operation = Union | Intersection | Difference | Reverse_difference | Xor

val prepare :
  ?cancel:Cancel.t ->
    ?resolve_left_self_intersections:bool ->
    ?resolve_right_self_intersections:bool ->
    ?left_treatment:treatment -> ?right_treatment:treatment ->
  grain:int -> left:Geometry.t -> right:Geometry.t ->
  unit -> (t, Error.t) result
(** Construct and classify the shared two-operand arrangement once. Degenerate
    source triangle pairs are rejected until their repair policy is explicit.
    Self-intersection resolution is opt-in per operand so known-clean solids do
    not pay for self broad phases. [Surface] operands remain exact arrangement
    constraints and seam contributors but add zero to volumetric winding. *)

val extract :
  ?cancel:Cancel.t -> ?require_closed:bool ->
  expression:Boolean_extract.expression -> t -> (Geometry.t, Error.t) result
(** Evaluate an expression without repeating intersection, refinement, radial,
    or cell-classification work. *)

val extract_with_ancestry :
  ?cancel:Cancel.t -> ?require_closed:bool -> ?defer_rounded_slivers:bool ->
  expression:Boolean_extract.expression -> t ->
  (Boolean_extract.ancestry, Error.t) result

val extract_product :
  ?cancel:Cancel.t -> ?require_closed:bool -> operation:operation -> t ->
  (Geometry.t, Error.t) result
val extract_product_with_ancestry :
  ?cancel:Cancel.t -> ?require_closed:bool -> ?defer_rounded_slivers:bool ->
  operation:operation -> t ->
  (Boolean_extract.ancestry, Error.t) result
(** Treatment-aware solid/surface product extraction. Sheet facets remain
    zero-volume arrangement constraints and are emitted explicitly, including
    paired opposite-facing walls for a solid-minus-surface cut. *)

val seams :
  ?cancel:Cancel.t -> ?grain:int -> ?parallel_cutoff:int ->
  t -> (Boolean_seam.t, Error.t) result
(** Materialize deterministic self/intersection curves and coincident facets
    from the already prepared exact complex without repeating arrangement. *)

val shatter_with_ancestry :
  ?cancel:Cancel.t -> ?require_closed:bool -> ?defer_rounded_slivers:bool -> t ->
  (Boolean_extract.ancestry array, Error.t) result
(** Extract stable A-only, overlap, and B-only closed region boundaries from
    one prepared arrangement. Shared walls are intentionally duplicated
    between products. *)

val vertex_count : t -> int
val facet_count : t -> int
val shell_count : t -> int

module Private : sig
  val constraints : t -> Boolean_constraints.t
  val complex : t -> Boolean_complex.t
  val radial : t -> Boolean_radial.t
  val weiler : t -> Boolean_weiler.t
  val cells : t -> Boolean_cells.t
  val left_treatment : t -> treatment
  val right_treatment : t -> treatment
end
