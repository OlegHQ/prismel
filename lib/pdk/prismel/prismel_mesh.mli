open Pdk_core
(** Explicit bridge to Prismel's renderer mesh. Triangle-ready point position
    and normal planes and indices are shared without copying. Point and vertex
    [N], [Cd], and [uv] attributes are preserved; vertex-owned attributes cause
    deterministic corner expansion because Prismel's render mesh has one
    attribute tuple per render vertex. Both values remain immutable. *)

val to_mesh : ?cancel:Cancel.t -> Geometry.t -> (Prismel.Mesh.t, Error.t) result
val to_mesh_with_primitives :
  ?cancel:Cancel.t -> Geometry.t -> (Prismel.Mesh.t * int array, Error.t) result
(** [to_mesh] and, for every triangle of the mesh in order, the primitive of
    [geometry] it came from (a polygon of n corners is n - 2 triangles).  [||]
    for points and curves.  Costs one primitive attribute and the triangulation
    [to_mesh] does anyway; ask only when triangles must be traced back (a CPU
    pick, the ID-buffer upgrade of the viewport pick). *)

val of_mesh : ?cancel:Cancel.t -> Prismel.Mesh.t -> (Geometry.t, Error.t) result
