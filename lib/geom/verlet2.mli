(** Immutable two-dimensional Verlet particle physics. *)

open Prismel

type particle
type spring = private {
  a : int;
  b : int;
  rest_length : float;
  strength : float;
  min_length : float option;
}
type behavior = particle -> dt:float -> Vec2.t
type constraint_ = particle -> particle
type t

val particle : ?mass:float -> ?locked:bool -> ?velocity:Vec2.t -> Vec2.t -> particle
val position : particle -> Vec2.t
val previous_position : particle -> Vec2.t
val velocity : particle -> Vec2.t
val mass : particle -> float
val locked : particle -> bool
val lock : particle -> particle
val unlock : particle -> particle
val with_position : ?preserve_velocity:bool -> Vec2.t -> particle -> particle
val with_velocity : Vec2.t -> particle -> particle
val add_force : Vec2.t -> particle -> particle
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

val gravity : Vec2.t -> behavior
val attract : center:Vec2.t -> radius:float -> strength:float -> behavior
val align : velocity:Vec2.t -> strength:float -> behavior

val inside_bounds : Bounds2.t -> constraint_
val outside_circle : Circle2.t -> constraint_
val inside_circle : Circle2.t -> constraint_
val on_circle : Circle2.t -> constraint_
