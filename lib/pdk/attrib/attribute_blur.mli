type method_ = Uniform | Edge_length
type mode = Laplacian of float | Custom_steps of { odd : float; even : float }

val run :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:Group.t ->
  ?iterations:int -> ?method_:method_ -> ?mode:mode ->
  ?weight_attribute:string -> ?alpha_attribute:string ->
  ?pin_borders:bool -> ?original_blend:float -> ?blurred_blend:float ->
  pattern:string -> Geometry.t -> (Geometry.t, Error.t) result
