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
val finite3 : Prismel_math.Vec3.t -> bool
val fract : float -> float
val point_int_optional :
  string -> Pdk_core.Geometry.t -> (int array option, string) result
val point_float3_optional :
  string ->
  Pdk_core.Geometry.t ->
  (Pdk_core.Packed.Float3.Private.view option, string) result
val fresh_point_name : string -> Pdk_core.Geometry.t -> string
val radical_inverse : int -> int -> float
type sample_scratch = float array
type quasi_data = {
  offset_u : float array;
  offset_v : float array;
  offset_w : float array;
  sequence_v : float array;
  sequence_w : float array;
}
val create_sample_scratch : unit -> float array
val sample_coordinates_into :
  float array ->
  quasi:quasi_data option ->
  seed:Prismel_math.Rand.t ->
  identity:int -> source:int -> local:int -> count:int -> unit
val local_shape_into :
  float array -> shape -> Pdk_core.Packed.Float3.Private.view option -> int
val make_basis : unit -> Pdk_core.Geometry.t
val transform_inherited_attributes :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  pattern:Pdk_core.Attribute_pattern.t option ->
  prefix:int ->
  source_map:int array ->
  counts:int array ->
  frame_positions:Pdk_core.Packed.Float3.Private.view ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?points:Pdk_core.Group.t ->
  ?keep_input:bool ->
  ?seed:Prismel_math.Rand.t ->
  ?id_attribute:string ->
  ?generated_group:string ->
  ?copy_point_attributes:string ->
  ?keep_source_attributes:bool ->
  ?transform_attributes:string ->
  ?source_point_attribute:String.t ->
  ?source_index_attribute:String.t ->
  ?shape:shape ->
  ?custom_shape:Pdk_core.Geometry.t ->
  ?center:Prismel_math.Vec3.t ->
  ?size:Prismel_math.Vec3.t ->
  ?orientation:Prismel_math.Vec3.t ->
  ?uniform_scale:float ->
  ?quasi_stratified:bool ->
  ?velocity_stretch:velocity_stretch ->
  ?velocity_scale:float ->
  ?inherit_velocity:float ->
  ?radial_velocity:float ->
  ?noise_amplitude:Prismel_math.Vec3.t ->
  ?noise_frequency:Prismel_math.Vec3.t ->
  ?noise_offset:Prismel_math.Vec3.t ->
  ?noise_roughness:float ->
  ?noise_attenuation:float ->
  ?noise_turbulence:int ->
  ?noise_seed:int ->
  copy_basis:(Pdk_core.Geometry.t ->
              Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result) ->
  points_per_point:float ->
  ?scale_attribute:string ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
