type vec3 = { x : float; y : float; z : float }
type kernel = Tap1 | Tap4 | Tap9
type bias = { constant : float; slope : float }
type light_kind = Directional | Spot
type error = Invalid_size | Invalid_matrix | Non_finite | Invalid_bias | Out_of_bounds
type t
type prepared

val create : width:int -> height:int -> (t, error) result
val clear : t -> depth:float -> (unit, error) result
val write : t -> x:int -> y:int -> depth:float -> (unit, error) result
val prepare : t -> light_kind:light_kind -> matrix:float array -> bias:bias ->
  kernel:kernel -> (prepared, error) result
(* Returns deterministic visibility in [0,1]. Outside the light frustum is lit. *)
val visibility : prepared -> position:vec3 -> normal_dot_light:float -> float
