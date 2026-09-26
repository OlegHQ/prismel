val noise_displace_checked :
  ?cancel:Cancel.t -> ?grain:int -> amplitude:float -> frequency:float ->
  seed:int -> Geometry.t -> (Geometry.t, Error.t) result

val peak_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:Element_selection.t ->
  ?direction_attribute:string -> ?normalize_direction:bool ->
  ?mask_attribute:string -> distance:float -> ?recompute_normals:bool ->
  Geometry.t -> (Geometry.t, Error.t) result

val bend_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:Element_selection.t ->
  ?mask_attribute:string -> ?origin:Prismel_math.Vec3.t ->
  ?direction:Prismel_math.Vec3.t -> ?up:Prismel_math.Vec3.t ->
  length:float -> ?bend_angle:float -> ?twist_angle:float ->
  ?limit:bool -> ?both_directions:bool -> ?continuous_twist:bool ->
  ?capture_attribute:string -> ?recompute_normals:bool ->
  Geometry.t -> (Geometry.t, Error.t) result

val mountain_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:Element_selection.t ->
  ?direction_attribute:string -> ?normalize_direction:bool ->
  ?mask_attribute:string -> ?seed:int -> height:float ->
  ?frequency:Prismel_math.Vec3.t -> ?offset:Prismel_math.Vec3.t ->
  ?octaves:int -> ?lacunarity:float -> ?roughness:float ->
  ?height_attribute:string -> ?recompute_normals:bool ->
  Geometry.t -> (Geometry.t, Error.t) result

val point_jitter_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?points:Group.t ->
  ?mask_attribute:string -> ?id_attribute:string ->
  ?use_point_scale:bool -> seed:Prismel_math.Rand.t -> scale:float ->
  ?axis_scales:Prismel_math.Vec3.t ->
  Geometry.t -> (Geometry.t, Error.t) result
