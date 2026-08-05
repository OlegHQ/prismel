(** Two-dimensional intersection and overlap queries. *)

open Prismel

type hit = {
  point : Vec2.t;
  distance : float;
  normal : Vec2.t;
}

val ray_segment : ?epsilon:float -> Ray2.t -> Segment2.t -> hit option
val ray_circle : ?epsilon:float -> Ray2.t -> Circle2.t -> hit list
val ray_bounds : ?epsilon:float -> Ray2.t -> Bounds2.t -> hit option
val ray_polygon : ?epsilon:float -> Ray2.t -> Polygon2.t -> hit list
val segment_circle : ?epsilon:float -> Segment2.t -> Circle2.t -> Vec2.t list
val segment_polygon : ?epsilon:float -> Segment2.t -> Polygon2.t -> Vec2.t list
val circle_bounds : Circle2.t -> Bounds2.t -> bool
val circle_polygon : ?epsilon:float -> Circle2.t -> Polygon2.t -> bool
val polygon_polygon : ?epsilon:float -> Polygon2.t -> Polygon2.t -> bool
