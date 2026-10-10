(** Unit quaternions for 3D orientation. *)

type t = { x : float; y : float; z : float; w : float }

val create : x:float -> y:float -> z:float -> w:float -> t
val normalize : t -> t
val mul : t -> t -> t
(* Return pitch (X), yaw/heading (Y), and roll (Z), in radians, matching
   [of_euler]. *)
