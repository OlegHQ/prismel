type deform_selection = Deform.selection =
  | Selected_points of Group.t
  | Selected_vertices of Group.t
  | Selected_primitives of Group.t
  | Selected_edges of Edge_group.t

type transform_order =
  | Transform_srt | Transform_str | Transform_rst
  | Transform_rts | Transform_tsr | Transform_trs

type transform_rotation_order =
  | Transform_xyz | Transform_xzy | Transform_yxz
  | Transform_yzx | Transform_zxy | Transform_zyx

type soft_transform_metric =
  | Soft_radius
  | Soft_edge
  | Soft_attribute of { attribute : string; apply_rolloff : bool }

type soft_transform_falloff = Soft_linear | Soft_quadratic | Soft_cubic

type distance_along_radius = Distance_fixed of float | Distance_maximum

type distance_from_geometry_reference =
  | Distance_reference_points | Distance_reference_primitives

type distance_from_target_projection =
  | Distance_target_spherical | Distance_target_cylindrical | Distance_target_planar

type distance_from_target_metric = Distance_target_absolute | Distance_target_signed

val compose_transform :
  ?order:transform_order -> ?rotation_order:transform_rotation_order ->
  ?translate:Prismel_math.Vec3.t -> ?rotate:Prismel_math.Vec3.t ->
  ?scale:Prismel_math.Vec3.t -> ?shear:Prismel_math.Vec3.t ->
  ?uniform_scale:float -> ?pivot:Prismel_math.Vec3.t ->
  ?pivot_rotation:Prismel_math.Vec3.t -> ?invert:bool -> unit ->
  (Prismel_math.Mat4.t, Error.t) result

val transform_selected :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:deform_selection ->
  ?preserve_normal_length:bool -> ?recompute_normals:bool ->
  Prismel_math.Mat4.t -> Geometry.t -> (Geometry.t, Error.t) result

val soft_transform :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:deform_selection ->
  ?metric:soft_transform_metric -> ?falloff:soft_transform_falloff ->
  ?radius:float -> ?falloff_attribute:string -> ?recompute_normals:bool ->
  Prismel_math.Mat4.t -> Geometry.t -> (Geometry.t, Error.t) result

val distance_along_geometry :
  ?cancel:Cancel.t -> ?grain:int -> ?affected:deform_selection ->
  ?falloff:soft_transform_falloff -> ?radius:distance_along_radius ->
  ?distance_attribute:string option -> ?mask_attribute:string ->
  start:deform_selection -> Geometry.t -> (Geometry.t, Error.t) result

val distance_from_geometry :
  ?cancel:Cancel.t -> ?grain:int -> ?affected:deform_selection ->
  ?reference_selection:deform_selection ->
  ?reference_kind:distance_from_geometry_reference ->
  ?falloff:soft_transform_falloff -> ?radius:distance_along_radius ->
  ?distance_attribute:string option -> ?mask_attribute:string ->
  reference:Geometry.t -> Geometry.t -> (Geometry.t, Error.t) result

val distance_from_target :
  ?cancel:Cancel.t -> ?grain:int -> ?affected:deform_selection ->
  ?projection:distance_from_target_projection ->
  ?origin:Prismel_math.Vec3.t -> ?direction:Prismel_math.Vec3.t ->
  ?metric:distance_from_target_metric -> ?falloff:soft_transform_falloff ->
  ?radius:distance_along_radius -> ?distance_attribute:string option ->
  ?mask_attribute:string -> Geometry.t -> (Geometry.t, Error.t) result

val transform : ?grain:int -> Prismel_math.Mat4.t -> Geometry.t -> Geometry.t
