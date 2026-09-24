(** Immutable three-dimensional Verlet particle physics. *)

open Prismel

type particle
type spring = private {
  a : int;
  b : int;
  rest_length : float;
  strength : float;
  min_length : float option;
}
type behavior = particle -> dt:float -> Vec3.t
type constraint_ = particle -> particle
type t

val particle : ?mass:float -> ?locked:bool -> ?velocity:Vec3.t -> Vec3.t -> particle
val position : particle -> Vec3.t
val previous_position : particle -> Vec3.t
val velocity : particle -> Vec3.t
val mass : particle -> float
val locked : particle -> bool
val lock : particle -> particle
val unlock : particle -> particle
val with_position : ?preserve_velocity:bool -> Vec3.t -> particle -> particle
val with_velocity : Vec3.t -> particle -> particle
val add_force : Vec3.t -> particle -> particle
val clear_force : particle -> particle
val add_behavior : behavior -> particle -> particle
val add_constraint : constraint_ -> particle -> particle

val spring : ?strength:float -> ?rest_length:float -> int -> int -> spring
val pullback_spring : ?strength:float -> rest_length:float -> min_length:float -> int -> int -> spring

val create :
  ?drag:float ->
  ?iterations:int ->
  ?behaviors:behavior list ->
  ?constraints:constraint_ list ->
  particle list ->
  spring list ->
  (t, string) result
val particles : t -> particle list
val springs : t -> spring list
val particle_count : t -> int
val particle_at : int -> t -> particle option
val with_particle : int -> particle -> t -> (t, string) result
val add_particle : particle -> t -> t
val add_spring : spring -> t -> (t, string) result
val add_behavior_to_world : behavior -> t -> t
val add_constraint_to_world : constraint_ -> t -> t
val step : dt:float -> t -> t

val gravity : Vec3.t -> behavior
val attract : center:Vec3.t -> radius:float -> strength:float -> behavior
val align : velocity:Vec3.t -> strength:float -> behavior

val inside_bounds : Bounds3.t -> constraint_
val outside_sphere : Sphere3.t -> constraint_
val inside_sphere : Sphere3.t -> constraint_
val on_sphere : Sphere3.t -> constraint_
