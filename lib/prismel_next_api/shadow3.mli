(** Deterministic depth-map shadows for [Scene3]. *)

type filter = Hard | Pcf_3x3 | Pcf_5x5
type t

val create :
  ?bias:float ->
  ?normal_bias:float ->
  ?filter:filter ->
  ?strength:float ->
  light:Light.t ->
  camera:Camera.t ->
  width:int ->
  height:int ->
  depths:float array ->
  unit ->
  t

val light : t -> Light.t
val filter : t -> filter
val size : t -> int * int

module Private : sig
  type snapshot = {
    view_projection : Mat4.t;
    width : int;
    height : int;
    depths : float array;
    bias : float;
    normal_bias : float;
    filter : filter;
    strength : float;
  }
  val affects : t -> Light.t -> bool
  val visibility : t -> world:Vec3.t -> normal:Vec3.t -> float
  val snapshot : t -> snapshot
end
