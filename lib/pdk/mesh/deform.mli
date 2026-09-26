type selection =
  Pdk_core.Element_selection.t =
    Selected_points of Pdk_core.Group.t
  | Selected_vertices of Pdk_core.Group.t
  | Selected_primitives of Pdk_core.Group.t
  | Selected_edges of Pdk_core.Edge_group.t
type planes = { x : float array; y : float array; z : float array; }
val validate_selection :
  Pdk_core.Topology.t -> selection option -> (unit, string) result
val selection_needs_index : selection option -> bool
val point_selected :
  selection option -> Pdk_core.Topology_index.t option -> int -> bool
val point_vector_attribute :
  string -> String.t -> Pdk_core.Geometry.t -> (planes, string) result
val face_vectors :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  ?primitives:Pdk_core.Group.t ->
  Pdk_core.Geometry.t -> (planes, string) result
val geometric_point_vectors :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  ?primitives:Pdk_core.Group.t ->
  Pdk_core.Geometry.t -> (planes, string) result
val resolve_directions :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  ?direction_attribute:String.t ->
  Pdk_core.Geometry.t -> (planes, string) result
val normals :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  ?primitives:Pdk_core.Group.t ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val peak :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:selection ->
  ?direction_attribute:string -> ?normalize_direction:bool ->
  ?mask_attribute:string -> distance:float -> ?recompute_normals:bool ->
  Geometry.t -> (Geometry.t, Error.t) result

val bend :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:selection ->
  ?mask_attribute:string -> ?origin:Prismel_math.Vec3.t ->
  ?direction:Prismel_math.Vec3.t -> ?up:Prismel_math.Vec3.t ->
  length:float -> ?bend_angle:float -> ?twist_angle:float ->
  ?limit:bool -> ?both_directions:bool -> ?continuous_twist:bool ->
  ?capture_attribute:string -> ?recompute_normals:bool ->
  Geometry.t -> (Geometry.t, Error.t) result

val mountain :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:selection ->
  ?direction_attribute:string -> ?normalize_direction:bool ->
  ?mask_attribute:string -> ?seed:int -> height:float ->
  ?frequency:Prismel_math.Vec3.t -> ?offset:Prismel_math.Vec3.t ->
  ?octaves:int -> ?lacunarity:float -> ?roughness:float ->
  ?height_attribute:string -> ?recompute_normals:bool ->
  Geometry.t -> (Geometry.t, Error.t) result

val noise_displace :
  ?cancel:Cancel.t -> ?grain:int -> amplitude:float -> frequency:float ->
  seed:int -> Geometry.t -> (Geometry.t, Error.t) result
