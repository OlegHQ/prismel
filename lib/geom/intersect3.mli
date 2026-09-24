(** Three-dimensional intersection and overlap queries. *)

open Prismel

type hit = {
  point : Vec3.t;
  distance : float;
  normal : Vec3.t;
  barycentric : (float * float * float) option;
}

val ray_plane : ?epsilon:float -> Ray3.t -> Plane3.t -> hit option
val ray_sphere : ?epsilon:float -> Ray3.t -> Sphere3.t -> hit list
val ray_bounds : ?epsilon:float -> Ray3.t -> Bounds3.t -> hit option
val ray_triangle : ?epsilon:float -> Ray3.t -> Triangle3.t -> hit option
val sphere_sphere : Sphere3.t -> Sphere3.t -> bool
val sphere_bounds : Sphere3.t -> Bounds3.t -> bool
val sphere_triangle : Sphere3.t -> Triangle3.t -> bool
val plane_sphere : ?epsilon:float -> Plane3.t -> Sphere3.t -> bool
val plane_bounds : ?epsilon:float -> Plane3.t -> Bounds3.t -> bool
val plane_plane : ?epsilon:float -> Plane3.t -> Plane3.t -> Ray3.t option
val triangle_bounds : ?epsilon:float -> Triangle3.t -> Bounds3.t -> bool
val tetrahedron_tetrahedron :
  ?epsilon:float -> Tetrahedron3.t -> Tetrahedron3.t -> bool
