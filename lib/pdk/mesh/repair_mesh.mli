(** Packed triangle topology diagnostics and repair. *)

type edge = { a : int; b : int }
type report = {
  faces : int;
  components : int;
  boundary_edges : edge list;
  non_manifold_edges : edge list;
  degenerate_faces : int list;
  duplicate_faces : int list;
}

val analyze :
  ?cancel:Cancel.t -> ?epsilon:float -> Geometry.t -> (report, Error.t) result
val is_closed : report -> bool
val is_manifold : report -> bool
val repair_t_junctions :
  ?cancel:Cancel.t -> ?epsilon:float -> Geometry.t -> (Geometry.t, Error.t) result
val orient_consistently :
  ?cancel:Cancel.t -> Geometry.t -> (Geometry.t, Error.t) result
