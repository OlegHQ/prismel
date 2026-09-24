(** Surface properties for 3D lighting. *)

type t = {
  diffuse : Color.t;
  ambient : Color.t;
  specular : Color.t;
  emissive : Color.t;
  shininess : float;
}

val create :
  ?diffuse:Color.t ->
  ?ambient:Color.t ->
  ?specular:Color.t ->
  ?emissive:Color.t ->
  ?shininess:float ->
  unit ->
  t

val default : t
val matte : Color.t -> t
val unlit : Color.t -> t
