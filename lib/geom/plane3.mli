(** Normalized three-dimensional planes [dot normal point = offset]. *)

open Prismel

type t = private { normal : Vec3.t; offset : float }

val make : normal:Vec3.t -> offset:float -> t
val through : normal:Vec3.t -> point:Vec3.t -> t
val through_three_points : ?epsilon:float -> Vec3.t -> Vec3.t -> Vec3.t -> t option
val signed_distance : t -> Vec3.t -> float
val classify : ?epsilon:float -> t -> Vec3.t -> [ `Back | `Coplanar | `Front ]
val project : t -> Vec3.t -> Vec3.t
val reflect_point : t -> Vec3.t -> Vec3.t
val flip : t -> t
