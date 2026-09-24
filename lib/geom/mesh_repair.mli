(** Triangle-mesh topology diagnostics and repair. *)

open Prismel

type edge = private { a : int; b : int }

type report = private {
  faces : int;
  components : int;
  boundary_edges : edge list;
  non_manifold_edges : edge list;
  degenerate_faces : int list;
  duplicate_faces : int list;
}

val analyze : ?epsilon:float -> Mesh.t -> report
val is_closed : report -> bool
val is_manifold : report -> bool

val weld : ?epsilon:float -> Mesh.t -> Mesh.t
(** Merge vertices only when positions and all present attributes agree. *)

val remove_degenerate : ?epsilon:float -> Mesh.t -> (Mesh.t, string) result
val remove_duplicate_faces : Mesh.t -> (Mesh.t, string) result
val collapse_short_edges : epsilon:float -> Mesh.t -> (Mesh.t, string) result
(** Collapse triangle edges shorter than [epsilon], then remove degenerate and
    duplicate faces. *)

val repair_t_junctions : ?epsilon:float -> Mesh.t -> (Mesh.t, string) result
(** Split triangle edges wherever an existing mesh vertex lies in their
    interior. Vertex attributes are preserved because no new vertices are
    introduced. *)

val make_watertight : ?epsilon:float -> Mesh.t -> (Mesh.t, string) result
(** Repair T-junctions and consistently orient the resulting mesh. *)

val orient_consistently : Mesh.t -> (Mesh.t, string) result
(** Propagate coherent winding across shared edges. Closed components are then
    flipped when necessary to have positive signed volume. *)

val repair :
  ?weld_epsilon:float ->
  ?degenerate_epsilon:float ->
  ?t_junction_epsilon:float ->
  Mesh.t ->
  (Mesh.t, string) result
(** Weld, remove degenerate/duplicate faces, and orient components. *)
