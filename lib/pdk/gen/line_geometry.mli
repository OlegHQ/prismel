(** Packed point clouds and straight/open/closed polylines. *)

type kind = Line_curve | Line_points

val points : (float * float * float) array -> Geometry.t

val line_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?kind:kind -> ?points:int ->
  origin:Prismel_math.Vec3.t -> direction:Prismel_math.Vec3.t -> length:float -> unit ->
  (Geometry.t, Error.t) result

val polyline_checked :
  ?closed:bool -> (float * float * float) array ->
  (Geometry.t, Error.t) result
