(** Indexed regular convex polyhedra centered at the origin. *)

open Prismel

type kind =
  | Tetrahedron
  | Cube
  | Octahedron
  | Icosahedron
  | Dodecahedron
  | Soccer_ball

val vertices : kind -> radius:float -> Vec3.t list
val mesh : ?flat:bool -> kind -> radius:float -> Mesh.t
val tetrahedron : ?flat:bool -> radius:float -> unit -> Mesh.t
val cube : ?flat:bool -> radius:float -> unit -> Mesh.t
val octahedron : ?flat:bool -> radius:float -> unit -> Mesh.t
val icosahedron : ?flat:bool -> radius:float -> unit -> Mesh.t
val dodecahedron : ?flat:bool -> radius:float -> unit -> Mesh.t
val soccer_ball : ?flat:bool -> radius:float -> unit -> Mesh.t
