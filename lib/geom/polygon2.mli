(** Immutable simple polygons.

    Constructors remove a repeated closing vertex. Polygon operations preserve
    winding unless documented otherwise. *)

open Prismel

type t
type triangle = Vec2.t * Vec2.t * Vec2.t

val create : Vec2.t list -> (t, string) result
val create_exn : Vec2.t list -> t
val vertices : t -> Vec2.t list
val vertex_count : t -> int
val edges : t -> Segment2.t list

val signed_area : t -> float
val area : t -> float
val clockwise : t -> bool
val centroid : t -> Vec2.t
val perimeter : t -> float
val bounds : t -> Bounds2.t
val contains : ?epsilon:float -> t -> Vec2.t -> bool
val closest_point : t -> Vec2.t -> Vec2.t
val point_at : t -> float -> Vec2.t
(** Evaluate by normalized arc length. Amount wraps into the half-open interval
    from zero to one. *)

val sample_uniform :
  ?include_last:bool -> distance:float -> t -> Vec2.t list

val map : (Vec2.t -> Vec2.t) -> t -> t
val transform : Affine2.t -> t -> t
val translate : Vec2.t -> t -> t
val rotate : ?center:Vec2.t -> float -> t -> t
val scale : ?center:Vec2.t -> Vec2.t -> t -> t
val reverse : t -> t
val smooth : ?iterations:int -> ?ratio:float -> t -> Curve2.t
(** Convert the polygon boundary to a closed Chaikin-smoothed curve. *)

val convex_hull : Vec2.t list -> t option
val clip_convex : subject:t -> clip:t -> t option
(** Sutherland-Hodgman clipping. [clip] must be convex. *)

val inset : distance:float -> t -> (t, string) result
(** Offset each edge toward the polygon interior. Large distances can collapse
    or self-intersect concave polygons and return an error. *)

val triangulate : t -> (triangle list, string) result
(** Ear-clipping tessellation for simple polygons, including concave ones. *)

val regular :
  ?rotation:float -> center:Vec2.t -> radius:float -> sides:int -> unit -> t
val star :
  ?rotation:float ->
  center:Vec2.t ->
  inner_radius:float ->
  outer_radius:float ->
  points:int ->
  unit ->
  t
val cog :
  ?rotation:float ->
  center:Vec2.t ->
  radius:float ->
  teeth:int ->
  profile:float list ->
  unit ->
  t
(** Repeat radial profile multipliers around a circle. *)
