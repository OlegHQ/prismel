(** Immutable planar convex quadrilaterals. *)

open Prismel

type t = private { a : Vec3.t; b : Vec3.t; c : Vec3.t; d : Vec3.t }

val make : ?epsilon:float -> Vec3.t -> Vec3.t -> Vec3.t -> Vec3.t -> (t, string) result
val square : ?center:Vec3.t -> size:float -> unit -> t
val vertices : t -> Vec3.t list
val edges : t -> Segment3.t list
val normal : t -> Vec3.t
val area : t -> float
val perimeter : t -> float
val centroid : t -> Vec3.t
val bounds : t -> Bounds3.t
val contains : ?epsilon:float -> t -> Vec3.t -> bool
val inset : distance:float -> t -> (t, string) result
val transform : Mat4.t -> t -> t
val to_mesh : ?flat:bool -> t -> Mesh.t
