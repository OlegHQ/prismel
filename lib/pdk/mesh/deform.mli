type selection =
  Pdk_core.Element_selection.t =
    Selected_points of Pdk_core.Group.t
  | Selected_vertices of Pdk_core.Group.t
  | Selected_primitives of Pdk_core.Group.t
  | Selected_edges of Pdk_core.Edge_group.t
type planes = { x : float array; y : float array; z : float array; }
val finite_vec3 : Prismel_math.Vec3.t -> bool
val max_abs3 : float -> float -> float -> float
val validate_selection :
  Pdk_core.Topology.t -> selection option -> (unit, string) result
val selection_needs_index : selection option -> bool
val point_selected :
  selection option -> Pdk_core.Topology_index.t option -> int -> bool
val point_float_attribute :
  string -> string -> Pdk_core.Geometry.t -> (float array, string) result
val point_vector_attribute :
  string -> String.t -> Pdk_core.Geometry.t -> (planes, string) result
val vertex_normals : Pdk_core.Geometry.t -> (planes option, string) result
val face_vectors :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  ?primitives:Pdk_core.Group.t ->
  Pdk_core.Geometry.t -> (planes, string) result
val point_vectors_from_vertices :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int -> Pdk_core.Topology.t -> planes -> planes
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
val normalize_planes :
  ?cancel:Pdk_core.Cancel.t -> grain:int -> planes -> (planes, string) result
val with_point_normals :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  ?primitives:Pdk_core.Group.t ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val normals :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  ?primitives:Pdk_core.Group.t ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val prepare :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  ?selection:selection ->
  ?direction_attribute:String.t ->
  ?mask_attribute:string ->
  Pdk_core.Geometry.t ->
  (Pdk_core.Topology_index.t option * planes * float array option, string)
  result
val validate_noop :
  ?selection:selection ->
  ?direction_attribute:String.t ->
  ?mask_attribute:string -> Pdk_core.Geometry.t -> (unit, string) result
val finish_positions :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  recompute_normals:bool ->
  Pdk_core.Geometry.t ->
  float array ->
  float array -> float array -> (Pdk_core.Geometry.t, string) result
val peak :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  ?selection:selection ->
  ?direction_attribute:String.t ->
  normalize_direction:bool ->
  ?mask_attribute:string ->
  distance:float ->
  recompute_normals:bool ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val normalize3 : float -> float -> float -> (float * float * float) option
val capture_frame :
  Prismel_math.Vec3.t ->
  Prismel_math.Vec3.t ->
  Prismel_math.Vec3.t ->
  (float * float * float * float * float * float * float * float * float,
   string)
  result
val sinc : float -> float
val cosc : float -> float
val install_point_float :
  string ->
  float array -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val bend :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  ?selection:selection ->
  ?mask_attribute:string ->
  origin:Prismel_math.Vec3.t ->
  direction:Prismel_math.Vec3.t ->
  up:Prismel_math.Vec3.t ->
  length:float ->
  bend_angle:float ->
  twist_angle:float ->
  limit:bool ->
  both_directions:bool ->
  continuous_twist:bool ->
  ?capture_attribute:String.t ->
  recompute_normals:bool ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val initial_height_attribute :
  string option ->
  int ->
  Pdk_core.Geometry.t -> ((string * float array) option, string) result
val mountain :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  ?selection:selection ->
  ?direction_attribute:String.t ->
  normalize_direction:bool ->
  ?mask_attribute:string ->
  seed:int ->
  height:float ->
  frequency:Prismel_math.Vec3.t ->
  offset:Prismel_math.Vec3.t ->
  octaves:int ->
  lacunarity:float ->
  roughness:float ->
  ?height_attribute:string ->
  recompute_normals:bool ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
