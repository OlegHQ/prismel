(** Persistent hierarchical 3D transforms, corresponding to openFrameworks'
    [ofNode] without mutable parent pointers. *)

type t

val create :
  ?position:Vec3.t ->
  ?orientation:Quat.t ->
  ?scale:Vec3.t ->
  ?parent:t ->
  unit ->
  t

val position : t -> Vec3.t
val orientation : t -> Quat.t
val scale : t -> Vec3.t
val parent : t -> t option

val with_position : Vec3.t -> t -> t
val with_orientation : Quat.t -> t -> t
val with_scale : Vec3.t -> t -> t
val with_parent : ?maintain_global:bool -> t -> t -> t
val clear_parent : ?maintain_global:bool -> t -> t

val local_transform : t -> Mat4.t
val global_transform : t -> Mat4.t
val global_position : t -> Vec3.t
val global_orientation : t -> Quat.t
val global_scale : t -> Vec3.t
val euler : t -> Vec3.t
val pitch : t -> float
val heading : t -> float
val roll_angle : t -> float

val x_axis : t -> Vec3.t
val y_axis : t -> Vec3.t
val z_axis : t -> Vec3.t
val look_direction : t -> Vec3.t

val set_global_position : Vec3.t -> t -> t
val set_global_orientation : Quat.t -> t -> t
val move : Vec3.t -> t -> t
val truck : float -> t -> t
val boom : float -> t -> t
val dolly : float -> t -> t
val rotate : Quat.t -> t -> t
val rotate_axis : axis:Vec3.t -> float -> t -> t
val rotate_around : point:Vec3.t -> Quat.t -> t -> t
val pan : float -> t -> t
val tilt : float -> t -> t
val roll : float -> t -> t
val look_at : ?up:Vec3.t -> Vec3.t -> t -> t
val orbit :
  center:Vec3.t -> azimuth:float -> elevation:float -> radius:float -> t -> t
val local_to_global_point : t -> Vec3.t -> Vec3.t
val global_to_local_point : t -> Vec3.t -> Vec3.t option
val local_to_global_direction : t -> Vec3.t -> Vec3.t
val global_to_local_direction : t -> Vec3.t -> Vec3.t option
val reset : t -> t
