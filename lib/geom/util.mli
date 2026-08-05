(** Shared pure geometry helpers not owned by one shape type. *)

open Prismel

val centroid2 : Vec2.t list -> Vec2.t option
val centroid3 : Vec3.t list -> Vec3.t option
val bounding_circle : Vec2.t list -> Circle2.t option
val bounding_sphere : Vec3.t list -> Sphere3.t option

val map_bilinear :
  a:Vec3.t -> b:Vec3.t -> c:Vec3.t -> d:Vec3.t -> u:float -> v:float -> Vec3.t
val map_trilinear :
  p000:Vec3.t -> p100:Vec3.t -> p110:Vec3.t -> p010:Vec3.t ->
  p001:Vec3.t -> p101:Vec3.t -> p111:Vec3.t -> p011:Vec3.t ->
  u:float -> v:float -> w:float -> Vec3.t

val fit2 : ?uniform:bool -> source:Bounds2.t -> target:Bounds2.t -> unit -> Affine2.t
val fit3 : ?uniform:bool -> source:Bounds3.t -> target:Bounds3.t -> unit -> Mat4.t
val fit_points2 : ?uniform:bool -> target:Bounds2.t -> Vec2.t list -> Vec2.t list
val fit_points3 : ?uniform:bool -> target:Bounds3.t -> Vec3.t list -> Vec3.t list

val mesh_area : Mesh.t -> float
val mesh_volume : Mesh.t -> float
(** Absolute signed volume. Meaningful for closed, consistently oriented
    triangle meshes. *)
