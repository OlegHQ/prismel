(** Immutable circles and circle construction/intersection helpers. *)

open Prismel

type t = private {
  center : Vec2.t;
  radius : float;
}

val make : center:Vec2.t -> radius:float -> t
val area : t -> float
val circumference : t -> float
val contains : t -> Vec2.t -> bool
val bounds : t -> Bounds2.t
val point_at : t -> float -> Vec2.t
(** [point_at circle amount] uses turns, where 0.25 is a quarter rotation. *)

val sample : ?include_last:bool -> int -> t -> Vec2.t list
val transform : Affine2.t -> t -> (t, string) result
val intersections : ?epsilon:float -> t -> t -> Vec2.t list

(** Points on the circle whose tangent lines pass through the supplied point. *)
val tangent_points : ?epsilon:float -> t -> Vec2.t -> Vec2.t list

val through_three_points : ?epsilon:float -> Vec2.t -> Vec2.t -> Vec2.t -> t option
