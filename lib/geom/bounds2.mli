(** Axis-aligned 2D bounds. *)

open Prismel

type t = private {
  min : Vec2.t;
  max : Vec2.t;
}

val make : min:Vec2.t -> max:Vec2.t -> t
val of_points : Vec2.t list -> t option
val empty : t
val width : t -> float
val height : t -> float
val size : t -> Vec2.t
val center : t -> Vec2.t
val area : t -> float
val contains : t -> Vec2.t -> bool
val intersects : t -> t -> bool
val closest_point : t -> Vec2.t -> Vec2.t
val distance_sq : t -> Vec2.t -> float
val union : t -> t -> t
val include_point : Vec2.t -> t -> t
val expand : float -> t -> t
val corners : t -> Vec2.t list
val map_normalized : t -> Vec2.t -> Vec2.t
val unmap_normalized : t -> Vec2.t -> Vec2.t
