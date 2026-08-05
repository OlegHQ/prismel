(** Immutable light sources for [Scene3]. *)

type attenuation = {
  constant : float;
  linear : float;
  quadratic : float;
}

type kind =
  | Ambient
  | Directional of { direction : Vec3.t }
  | Point of { position : Vec3.t; attenuation : attenuation }
  | Spot of {
      position : Vec3.t;
      direction : Vec3.t;
      cutoff : float;
      concentration : float;
      attenuation : attenuation;
    }
  | Area of {
      position : Vec3.t;
      direction : Vec3.t;
      width : float;
      height : float;
      samples : int;
      attenuation : attenuation;
    }

type t = {
  kind : kind;
  diffuse : Color.t;
  ambient : Color.t;
  specular : Color.t;
  intensity : float;
}

val no_attenuation : attenuation
val attenuation :
  ?constant:float -> ?linear:float -> ?quadratic:float -> unit -> attenuation

val ambient : ?intensity:float -> Color.t -> t
val directional :
  ?diffuse:Color.t ->
  ?ambient:Color.t ->
  ?specular:Color.t ->
  ?intensity:float ->
  direction:Vec3.t ->
  unit ->
  t
val point :
  ?diffuse:Color.t ->
  ?ambient:Color.t ->
  ?specular:Color.t ->
  ?intensity:float ->
  ?attenuation:attenuation ->
  at:Vec3.t ->
  unit ->
  t

val spot :
  ?diffuse:Color.t ->
  ?ambient:Color.t ->
  ?specular:Color.t ->
  ?intensity:float ->
  ?attenuation:attenuation ->
  at:Vec3.t ->
  direction:Vec3.t ->
  cutoff:float ->
  concentration:float ->
  unit ->
  t
(** [cutoff] is the cone half-angle in radians. *)

val area :
  ?diffuse:Color.t ->
  ?ambient:Color.t ->
  ?specular:Color.t ->
  ?intensity:float ->
  ?attenuation:attenuation ->
  ?samples:int ->
  at:Vec3.t ->
  direction:Vec3.t ->
  width:float ->
  height:float ->
  unit ->
  t
(* [samples] is [1], [4], [9], or [16] deterministic surface samples. *)
