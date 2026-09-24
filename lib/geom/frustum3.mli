(** Immutable camera frusta and conservative intersection queries. *)

open Prismel

type t

val of_camera : viewport:int * int * int * int -> Camera.t -> t
val corners : t -> Vec3.t list
val planes : t -> Plane3.t list
val contains : ?epsilon:float -> t -> Vec3.t -> bool
val intersects_sphere : ?epsilon:float -> t -> Sphere3.t -> bool
val intersects_bounds : ?epsilon:float -> t -> Bounds3.t -> bool
val to_mesh : t -> Mesh.t
