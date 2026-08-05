(** Axis-aligned three-dimensional bounds. *)

open Prismel

type t = private { min : Vec3.t; max : Vec3.t }

val make : min:Vec3.t -> max:Vec3.t -> t
val empty : t
val of_points : Vec3.t list -> t option
val include_point : Vec3.t -> t -> t
val union : t -> t -> t
val expand : float -> t -> t
val width : t -> float
val height : t -> float
val depth : t -> float
val size : t -> Vec3.t
val center : t -> Vec3.t
val volume : t -> float
val surface_area : t -> float
val contains : t -> Vec3.t -> bool
val intersects : t -> t -> bool
val closest_point : t -> Vec3.t -> Vec3.t
val distance_sq : t -> Vec3.t -> float
val corners : t -> Vec3.t list
val map_normalized : t -> Vec3.t -> Vec3.t
val unmap_normalized : t -> Vec3.t -> Vec3.t
