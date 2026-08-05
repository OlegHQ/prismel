(** Immutable three-dimensional tetrahedra. *)

open Prismel

type t = private { a : Vec3.t; b : Vec3.t; c : Vec3.t; d : Vec3.t }

val make : Vec3.t -> Vec3.t -> Vec3.t -> Vec3.t -> t
val regular : center:Vec3.t -> radius:float -> t
val signed_volume : t -> float
val volume : t -> float
val centroid : t -> Vec3.t
val bounds : t -> Bounds3.t
val barycentric :
  ?epsilon:float -> t -> Vec3.t -> (float * float * float * float) option
val contains : ?epsilon:float -> t -> Vec3.t -> bool
val orient_outward : t -> t
val faces : t -> Triangle3.t list
val transform : Mat4.t -> t -> t
