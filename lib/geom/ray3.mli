(** Normalized three-dimensional rays. *)

open Prismel

type t = private { origin : Vec3.t; direction : Vec3.t }

val make : origin:Vec3.t -> direction:Vec3.t -> t
val through : origin:Vec3.t -> Vec3.t -> t
val point_at : t -> float -> Vec3.t
val closest_parameter : t -> Vec3.t -> float
val closest_point : t -> Vec3.t -> Vec3.t
val distance : t -> Vec3.t -> float
val transform : Mat4.t -> t -> t
