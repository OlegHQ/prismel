(** Immutable 2D triangles and barycentric queries. *)

open Prismel

type t = private { a : Vec2.t; b : Vec2.t; c : Vec2.t }
type vertex = A | B | C

val make : Vec2.t -> Vec2.t -> Vec2.t -> t
val equilateral : ?rotation:float -> center:Vec2.t -> radius:float -> unit -> t
val equilateral_on : Vec2.t -> Vec2.t -> t
val signed_area : t -> float
val area : t -> float
val centroid : t -> Vec2.t
val bounds : t -> Bounds2.t
val barycentric : ?epsilon:float -> t -> Vec2.t -> (float * float * float) option
val contains : ?epsilon:float -> t -> Vec2.t -> bool
val closest_point : t -> Vec2.t -> Vec2.t
val altitude : vertex -> t -> Segment2.t
val circumcircle : ?epsilon:float -> t -> Circle2.t option
val transform : Affine2.t -> t -> t
val to_polygon : t -> Polygon2.t
