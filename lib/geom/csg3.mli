(** BSP-based constructive solid geometry for closed triangle meshes. *)

open Prismel

val union : ?epsilon:float -> Mesh.t -> Mesh.t -> (Mesh.t, string) result
val intersection : ?epsilon:float -> Mesh.t -> Mesh.t -> (Mesh.t, string) result
val difference : ?epsilon:float -> Mesh.t -> Mesh.t -> (Mesh.t, string) result
(** Boolean operations preserve interpolated normals and preserve colors/UVs
    when both inputs provide them. Results are triangulated. Inputs should be
    consistently oriented closed solids. *)
