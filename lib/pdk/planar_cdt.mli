(** Shared exact-predicate planar constraint-recovery kernel. *)

type t

module Private : sig
  type view = {
    triangle_points : int array;
    constraint_points : int array;
  }

  type workspace

  val view : t -> view
  val create_workspace : triangle_capacity:int -> workspace
  (** Create reusable, exclusively owned scratch storage. A workspace is not
      safe for overlapping builds. Returned [t] values never borrow it. *)
end

val build :
  ?cancel:Cancel.t ->
  ?workspace:Private.workspace ->
  point_count:int ->
  orient:(int -> int -> int -> Predicates.sign) ->
  incircle:(int -> int -> int -> int -> Predicates.sign) ->
  ?bounds_overlap:(int -> int -> int -> int -> bool) ->
  triangle_points:int array ->
  ?insert_points:int array ->
  ?flood_from_hull_boundary:bool ->
  constraint_points:int array ->
  ?constraint_winding:int array ->
  ?remove_outside_constraint_polygons:bool ->
  unit ->
  (t, string) result
(** [triangle_points] and [constraint_points] are packed triples and endpoint
    pairs. [insert_points] are exact-callback point indices not yet referenced
    by the input topology; each is inserted by an exact face/edge split before
    constraint recovery. Input triangles must be a counter-clockwise manifold triangulation;
    constraints must form a non-crossing PSLG whose open segments contain no
    other input point. Missing constraint edges are recovered by tracing and
    flipping crossed diagonals, then unconstrained edges are restored to a
    deterministic constrained-Delaunay state. [flood_from_hull_boundary]
    removes triangles reachable from any unconstrained convex-hull edge
    without crossing a constrained edge. [constraint_winding] supplies signed
    directed polygon-boundary multiplicity per input segment;
    [remove_outside_constraint_polygons] retains triangles with non-zero
    propagated winding. [workspace] amortizes topology planes and the edge
    table across sequential builds while keeping each result independently
    owned. *)

val triangle_count : t -> int
val triangle_point : t -> int -> int -> int
val constraint_count : t -> int
val constraint_first : t -> int -> int
val constraint_second : t -> int -> int
