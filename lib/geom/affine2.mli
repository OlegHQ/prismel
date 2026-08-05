(** Immutable 2D affine transformations.

    Values use the conventional six-coefficient form:
    {[ x' = a*x + c*y + e
       y' = b*x + d*y + f ]} *)

open Prismel

type t

val identity : t
val make : a:float -> b:float -> c:float -> d:float -> e:float -> f:float -> t
val translation : Vec2.t -> t
val rotation : float -> t
val scaling : Vec2.t -> t
val uniform_scaling : float -> t
val shear : Vec2.t -> t

val compose : t -> t -> t
(** [compose outer inner] applies [inner] first, then [outer]. *)

val apply : t -> Vec2.t -> Vec2.t
val apply_direction : t -> Vec2.t -> Vec2.t
val determinant : t -> float
val inverse : t -> t option
val coefficients : t -> float * float * float * float * float * float
