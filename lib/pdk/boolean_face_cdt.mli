(** Deterministic exact-predicate constrained Delaunay refinement of one face. *)

type t
type point_location = Walk | Exact_scan
type constraint_recovery = Trace | Edge_scan
type workspace

val create_workspace : unit -> workspace
(** Exclusively owned scratch reused across sequential face refinements. *)

val build :
  ?cancel:Cancel.t -> ?workspace:workspace -> ?point_location:point_location ->
  ?constraint_recovery:constraint_recovery ->
  Boolean_constraints.t ->
  Boolean_face_arrangement.t ->
  side:Boolean_face_arrangement.side -> triangle:int ->
  (t, Error.t) result
(** Insert the arrangement's exact-unique points, recover every constraint,
    and canonicalize unconstrained diagonals with exact incircle predicates.
    The default [Walk] locator follows packed triangle adjacency and falls back
    atomically to [Exact_scan] if a walk cannot progress; [Exact_scan] remains
    available as a compatibility oracle.

    A specialized packed edge table is updated only for the two triangles
    changed by a flip. The default [Trace] recovery walks the first endpoint's
    incident fan and then the crossed triangle chain, rejecting non-overlapping
    certified interval boxes before exact predicates. [Edge_scan] retains the
    stable exhaustive compatibility oracle. Delaunay repair uses a stable
    minimum-key dirty-edge heap. Storage is O(points + triangles + constraints
    + queued local edges); trace work is proportional to endpoint valence and
    locally crossed edges, except when an invariant failure deliberately falls
    back to the O(constraints*active_edges) exact oracle. *)

val point_count : t -> int
val approximate_point : t -> int -> float * float * float
val triangle_count : t -> int
val triangle_point : t -> int -> int -> int
val constraint_count : t -> int
val constraint_first : t -> int -> int
val constraint_second : t -> int -> int

module Private : sig
  val point : t -> int -> Implicit_point.t
  val global_point_token : t -> int -> int
  val source_winding : t -> int
end
