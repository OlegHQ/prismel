(** Read-only triangle topology plus immutable editing helpers. *)

open Prismel

type edge = private { a : int; b : int }
type t

val of_mesh : Mesh.t -> t
val mesh : t -> Mesh.t
val edges : t -> edge list
val edge_faces : edge -> t -> int list
val vertex_neighbors : int -> t -> int list
val vertex_faces : int -> t -> int list
val vertex_valence : int -> t -> int
val face_neighbors : int -> t -> int list
val connected_components : t -> int list list

val replace_vertex : int -> Vec3.t -> t -> (t, string) result
val remove_vertex : int -> t -> (t, string) result
val remove_faces : (int -> Mesh.face -> bool) -> t -> (t, string) result
