(** Butterfly and Doo-Sabin subdivision of packed triangle meshes.
    Output point [Cd] and [uv] are interpolated; point normals are recomputed.
    A single iteration uses O(points + faces + edges) auxiliary storage. *)

val butterfly :
  ?cancel:Cancel.t -> ?iterations:int -> ?omega:float ->
  Geometry.t -> (Geometry.t, Error.t) result

val doo_sabin :
  ?cancel:Cancel.t -> ?iterations:int ->
  Geometry.t -> (Geometry.t, Error.t) result
