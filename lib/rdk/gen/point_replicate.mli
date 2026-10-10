type shape =
    Replicate_point
  | Replicate_box
  | Replicate_sphere
  | Replicate_disk
  | Replicate_line
  | Replicate_custom
type velocity_stretch =
    Replicate_no_velocity_stretch
  | Replicate_scaled_velocity
  | Replicate_velocity_only
val error : string -> ('a, string) result
type quasi_data = {
  offset_u : float array;
  offset_v : float array;
  offset_w : float array;
  sequence_v : float array;
  sequence_w : float array;
}
val run :
  ?cancel:Rdk_core.Cancel.t ->
  ?grain:int ->
  ?points:Rdk_core.Group.t ->
  ?keep_input:bool ->
  ?seed:Rays_math.Rand.t ->
  ?id_attribute:string ->
  ?generated_group:string ->
  ?copy_point_attributes:string ->
  ?keep_source_attributes:bool ->
  ?transform_attributes:string ->
  ?source_point_attribute:String.t ->
  ?source_index_attribute:String.t ->
  ?shape:shape ->
  ?custom_shape:Rdk_core.Geometry.t ->
  ?center:Rays_math.Vec3.t ->
  ?size:Rays_math.Vec3.t ->
  ?orientation:Rays_math.Vec3.t ->
  ?uniform_scale:float ->
  ?quasi_stratified:bool ->
  ?velocity_stretch:velocity_stretch ->
  ?velocity_scale:float ->
  ?inherit_velocity:float ->
  ?radial_velocity:float ->
  ?noise_amplitude:Rays_math.Vec3.t ->
  ?noise_frequency:Rays_math.Vec3.t ->
  ?noise_offset:Rays_math.Vec3.t ->
  ?noise_roughness:float ->
  ?noise_attenuation:float ->
  ?noise_turbulence:int ->
  ?noise_seed:int ->
  copy_basis:(Rdk_core.Geometry.t ->
              Rdk_core.Geometry.t -> (Rdk_core.Geometry.t, string) result) ->
  points_per_point:float ->
  ?scale_attribute:string ->
  Rdk_core.Geometry.t -> (Rdk_core.Geometry.t, string) result
