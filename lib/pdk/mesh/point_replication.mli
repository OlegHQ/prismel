type shape = Point_replicate.shape =
  | Replicate_point
  | Replicate_box
  | Replicate_sphere
  | Replicate_disk
  | Replicate_line
  | Replicate_custom
type velocity_stretch = Point_replicate.velocity_stretch =
  | Replicate_no_velocity_stretch
  | Replicate_scaled_velocity
  | Replicate_velocity_only

val run_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?points:Group.t -> ?keep_input:bool ->
  ?seed:Prismel_math.Rand.t -> ?id_attribute:string ->
  ?generated_group:string -> ?copy_point_attributes:string ->
  ?keep_source_attributes:bool -> ?transform_attributes:string ->
  ?source_point_attribute:string -> ?source_index_attribute:string ->
  ?shape:shape -> ?custom_shape:Geometry.t ->
  ?center:Prismel_math.Vec3.t -> ?size:Prismel_math.Vec3.t ->
  ?orientation:Prismel_math.Vec3.t -> ?uniform_scale:float ->
  ?quasi_stratified:bool -> ?velocity_stretch:velocity_stretch ->
  ?velocity_scale:float -> ?inherit_velocity:float -> ?radial_velocity:float ->
  ?noise_amplitude:Prismel_math.Vec3.t ->
  ?noise_frequency:Prismel_math.Vec3.t -> ?noise_offset:Prismel_math.Vec3.t ->
  ?noise_roughness:float -> ?noise_attenuation:float ->
  ?noise_turbulence:int -> ?noise_seed:int -> points_per_point:float ->
  ?scale_attribute:string -> Geometry.t -> (Geometry.t, Error.t) result
