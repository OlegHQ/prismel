(** Unit quaternions for 3D orientation. *)

type t = { x : float; y : float; z : float; w : float }

val create : x:float -> y:float -> z:float -> w:float -> t
val identity : t
val normalize : t -> t
val conjugate : t -> t
val inverse : t -> t option
val mul : t -> t -> t
val axis_angle : axis:Vec3.t -> float -> t
val of_euler : pitch:float -> yaw:float -> roll:float -> t
(* Return pitch (X), yaw/heading (Y), and roll (Z), in radians, matching
   [of_euler]. *)
val to_euler : t -> Vec3.t
val to_mat4 : t -> Mat4.t
val of_mat4 : Mat4.t -> t
val rotate : t -> Vec3.t -> Vec3.t
val slerp : t -> t -> float -> t
val nearly_equal : t -> t -> eps:float -> bool
