(** Immutable sampled 2D curves.

    Curves are polylines with an explicit open/closed topology. Constructors
    and subdivision functions are pure; conversion to a Prismel scene is kept
    in {!Render2}. *)

open Prismel

type t

val create : ?closed:bool -> Vec2.t list -> (t, string) result
val create_exn : ?closed:bool -> Vec2.t list -> t
val points : t -> Vec2.t list
val point_count : t -> int
val closed : t -> bool
val segments : t -> Segment2.t list
val length : t -> float

val point_at : t -> float -> Vec2.t
(** Evaluate by normalized arc length. Open curves clamp to their endpoints;
    closed curves wrap. *)

val sample_uniform :
  ?include_last:bool -> distance:float -> t -> Vec2.t list
(** Resample at approximately [distance] units while distributing any
    remainder evenly. Closed curves omit the duplicate endpoint unless
    [include_last] is true. *)

val map : (Vec2.t -> Vec2.t) -> t -> t
val transform : Affine2.t -> t -> t
val translate : Vec2.t -> t -> t
val rotate : ?center:Vec2.t -> float -> t -> t
val scale : ?center:Vec2.t -> Vec2.t -> t -> t
val centroid : t -> Vec2.t
val bounds : t -> Bounds2.t

val chaikin : ?iterations:int -> ?ratio:float -> t -> t
(** Corner-cutting subdivision. Open curves retain their endpoints. *)

val cubic_subdivide : ?iterations:int -> t -> t
(** Uniform cubic B-spline subdivision. Each iteration inserts edge midpoints
    and smooths existing interior vertices. *)

val quadratic_bezier :
  ?resolution:int ->
  from_:Vec2.t ->
  control:Vec2.t ->
  to_:Vec2.t ->
  unit ->
  t

val cubic_bezier :
  ?resolution:int ->
  from_:Vec2.t ->
  control1:Vec2.t ->
  control2:Vec2.t ->
  to_:Vec2.t ->
  unit ->
  t

val catmull_rom :
  ?closed:bool ->
  ?tension:float ->
  ?resolution:int ->
  Vec2.t list ->
  (t, string) result
(** Interpolating cardinal spline through every supplied point. [resolution]
    is the number of line segments generated per spline span. *)

val spiral :
  center:Vec2.t ->
  start_radius:float ->
  end_radius:float ->
  turns:float ->
  resolution:int ->
  unit ->
  t

val rose :
  ?rotation:float ->
  center:Vec2.t ->
  radius:float ->
  petals:int ->
  resolution:int ->
  unit ->
  t

val superformula :
  ?rotation:float ->
  ?a:float ->
  ?b:float ->
  center:Vec2.t ->
  radius:float ->
  m:float ->
  n1:float ->
  n2:float ->
  n3:float ->
  resolution:int ->
  unit ->
  t
(** Sample Johan Gielis' superformula over one full turn. *)
