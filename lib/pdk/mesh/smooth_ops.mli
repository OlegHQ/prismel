type boundary = Smooth.boundary =
  | Smooth_free
  | Smooth_unshared
  | Smooth_group_boundary

val run_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t ->
  ?constrained_points:Group.t -> ?boundary:boundary -> ?iterations:int ->
  ?method_:Attribute_ops.blur_method -> ?mode:Attribute_ops.blur_mode ->
  ?weight_attribute:string -> ?alpha_attribute:string ->
  ?recompute_normals:bool -> ?original_blend:float ->
  ?smoothed_blend:float -> attributes:string -> Geometry.t ->
  (Geometry.t, Error.t) result
