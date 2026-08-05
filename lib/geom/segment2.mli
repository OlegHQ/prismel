(** Finite line segments and their geometric queries. *)

open Prismel

type t = private {
  a : Vec2.t;
  b : Vec2.t;
}

type intersection =
  | No_intersection
  | Parallel
  | Coincident
  | Point of {
      point : Vec2.t;
      along_self : float;
      along_other : float;
    }

val make : Vec2.t -> Vec2.t -> t
val direction : t -> Vec2.t
val length : t -> float
val length_sq : t -> float
val midpoint : t -> Vec2.t
val point_at : t -> float -> Vec2.t
val closest_parameter : t -> Vec2.t -> float
val closest_point : t -> Vec2.t -> Vec2.t
val distance : t -> Vec2.t -> float
val side : t -> Vec2.t -> float
val bounds : t -> Bounds2.t
val transform : Affine2.t -> t -> t

(** Reflect a point across the infinite line containing the segment. *)
val reflect_point : Vec2.t -> t -> Vec2.t

val reflect : mirror:t -> t -> t
val intersect : ?epsilon:float -> t -> t -> intersection
