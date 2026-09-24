(** Immutable three-dimensional spheres. *)

open Prismel

type t = private { center : Vec3.t; radius : float }

val make : center:Vec3.t -> radius:float -> t
val surface_area : t -> float
val volume : t -> float
val contains : t -> Vec3.t -> bool
val bounds : t -> Bounds3.t
val closest_point : t -> Vec3.t -> Vec3.t
val signed_distance : t -> Vec3.t -> float
val transform : Mat4.t -> t -> (t, string) result
