(** Deterministic 2D Delaunay triangulation and bounded Voronoi cells. *)

open Prismel

type triangle = private {
  a : Vec2.t;
  b : Vec2.t;
  c : Vec2.t;
}

type cell = {
  site : Vec2.t;
  polygon : Polygon2.t;
}

val triangulate : ?epsilon:float -> Vec2.t list -> triangle list
(** Bowyer-Watson triangulation. Duplicate points within [epsilon] are removed.
    Returned triangles use counter-clockwise winding. *)

val vertices : triangle -> Vec2.t * Vec2.t * Vec2.t
val edges : triangle -> Segment2.t list
val area : triangle -> float
val centroid : triangle -> Vec2.t
val circumcenter : ?epsilon:float -> triangle -> Vec2.t option
val contains : ?epsilon:float -> triangle -> Vec2.t -> bool

val unique_edges : triangle list -> Segment2.t list
(** Return every undirected triangulation edge exactly once. *)

val boundary_edges : triangle list -> Segment2.t list
(** Return edges used by exactly one triangle. *)

val voronoi_cells :
  ?epsilon:float -> bounds:Bounds2.t -> Vec2.t list -> cell list
(** Construct cells by clipping the bounds rectangle against pairwise
    perpendicular-bisector half-planes. Cells follow input site order after
    duplicate removal. *)
