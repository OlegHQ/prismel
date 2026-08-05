(** Explicit bridge to Prismel's renderer mesh. Triangle-ready point position
    and normal planes and indices are shared without copying. Point and vertex
    [N], [Cd], and [uv] attributes are preserved; vertex-owned attributes cause
    deterministic corner expansion because Prismel's render mesh has one
    attribute tuple per render vertex. Both values remain immutable. *)

val to_mesh : ?cancel:Cancel.t -> Geometry.t -> (Prismel.Mesh.t, Error.t) result
val of_mesh : ?cancel:Cancel.t -> Prismel.Mesh.t -> (Geometry.t, Error.t) result
