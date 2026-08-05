(** Finite three-dimensional line segments. *)

open Prismel

type t = private { a : Vec3.t; b : Vec3.t }

val make : Vec3.t -> Vec3.t -> t
val direction : t -> Vec3.t
val length : t -> float
val length_sq : t -> float
val midpoint : t -> Vec3.t
val point_at : t -> float -> Vec3.t
val closest_parameter : t -> Vec3.t -> float
val closest_point : t -> Vec3.t -> Vec3.t
val distance : t -> Vec3.t -> float
val bounds : t -> Bounds3.t
val transform : Mat4.t -> t -> t
val reflect : plane:Plane3.t -> t -> t
val closest_between : t -> t -> Vec3.t * Vec3.t
(** Closest points on both finite segments. *)
