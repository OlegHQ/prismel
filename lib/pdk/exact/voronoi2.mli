(** Bounded two-dimensional Voronoi cells in input site order. *)

type cell = {
  site : Prismel_math.Vec2.t;
  vertices : Prismel_math.Vec2.t list;
}

val cells :
  ?cancel:Cancel.t -> ?epsilon:float ->
  bounds:Prismel_math.Bounds2.t -> Prismel_math.Vec2.t list ->
  (cell list, Error.t) result
(** Pairwise half-plane clipping. Sites within [epsilon] of an earlier site
    are removed; empty and collapsed cells are omitted. *)
