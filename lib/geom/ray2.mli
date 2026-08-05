(** Normalized two-dimensional rays. *)

open Prismel

type t = private { origin : Vec2.t; direction : Vec2.t }

val make : origin:Vec2.t -> direction:Vec2.t -> t
val through : origin:Vec2.t -> Vec2.t -> t
val point_at : t -> float -> Vec2.t
val closest_parameter : t -> Vec2.t -> float
val closest_point : t -> Vec2.t -> Vec2.t
val distance : t -> Vec2.t -> float
val transform : Affine2.t -> t -> t
