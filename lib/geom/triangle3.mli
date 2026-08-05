(** Immutable 3D triangles and closest-point queries. *)

open Prismel

type t = private { a : Vec3.t; b : Vec3.t; c : Vec3.t }
type vertex = A | B | C

val make : Vec3.t -> Vec3.t -> Vec3.t -> t
val equilateral_on : normal:Vec3.t -> Vec3.t -> Vec3.t -> (t, string) result
val area : t -> float
val normal : t -> Vec3.t
val centroid : t -> Vec3.t
val bounds : t -> Bounds3.t
val barycentric : ?epsilon:float -> t -> Vec3.t -> (float * float * float) option
val contains : ?epsilon:float -> t -> Vec3.t -> bool
val closest_point : t -> Vec3.t -> Vec3.t
val altitude : vertex -> t -> Ray3.t
val transform : Mat4.t -> t -> t
