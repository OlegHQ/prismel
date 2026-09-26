type keep = Above | Below | All
exception Clip_error of string
val finite : float -> bool
val get_ok : ('a, string) result -> 'a
val clamp01 : float -> float
type builder = {
  mutable tokens : int array;
  mutable corner_a : int array;
  mutable corner_b : int array;
  mutable corner_t : float array;
  mutable corner_count : int;
  mutable offsets : int array;
  mutable kinds : bytes;
  mutable primitive_source : int array;
  mutable primitive_side : int array;
  mutable primitive_clipped : bool array;
  mutable primitive_cap : bool array;
  mutable primitive_count : int;
}
val grown_capacity : int -> int -> int
val grow_int : 'a array -> int -> 'a -> 'a array
val grow_float : float array -> int -> float array
val grow_bool : bool array -> int -> bool array
val grow_bytes : bytes -> int -> bytes
val trim_int : 'a array -> int -> 'a array
val trim_float : 'a array -> int -> 'a array
val trim_bool : 'a array -> int -> 'a array
val trim_bytes : bytes -> int -> bytes
val create_builder : corner_capacity:int -> primitive_capacity:int -> builder
val ensure_corners : builder -> int -> unit
val ensure_primitives : builder -> int -> unit
val add_corner : builder -> token:int -> a:int -> b:int -> t:float -> unit
val add_corner_unique :
  builder -> int -> token:int -> a:int -> b:int -> t:float -> unit
val drop_closing_duplicate : builder -> int -> unit
val finish_primitive :
  builder ->
  start:int ->
  kind:char ->
  source:int -> side:int -> clipped:bool -> cap:bool -> minimum:int -> bool
type segments = {
  mutable segment_a : int array;
  mutable segment_b : int array;
  mutable segment_side : int array;
  mutable segment_count : int;
}
val create_segments : int -> segments
val add_segment : segments -> a:int -> b:int -> side:int -> unit
val clip :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?keep:keep ->
  ?snapping_tolerance:float ->
  ?fill:bool ->
  ?split_connectivity:bool ->
  ?clip_attribute:String.t ->
  ?distance:float ->
  ?selection:Pdk_core.Element_selection.t ->
  ?replace_existing_groups:bool ->
  ?clipped_edge_group:string ->
  ?cap_group:string ->
  ?clipped_group:string ->
  ?above_group:string ->
  ?below_group:string ->
  origin:Prismel_math.Vec3.t ->
  normal:Prismel_math.Vec3.t ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result

type selection = Deform.selection =
  | Selected_points of Pdk_core.Group.t
  | Selected_vertices of Pdk_core.Group.t
  | Selected_primitives of Pdk_core.Group.t
  | Selected_edges of Pdk_core.Edge_group.t

val clip_checked :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?keep:keep ->
  ?snapping_tolerance:float ->
  ?fill:bool ->
  ?split_connectivity:bool ->
  ?clip_attribute:string ->
  ?distance:float ->
  ?selection:selection ->
  ?replace_existing_groups:bool ->
  ?clipped_edge_group:string ->
  ?cap_group:string ->
  ?clipped_group:string ->
  ?above_group:string ->
  ?below_group:string ->
  origin:Prismel_math.Vec3.t ->
  normal:Prismel_math.Vec3.t ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result

val clip_transform_checked :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?keep:keep ->
  ?snapping_tolerance:float ->
  ?fill:bool ->
  ?split_connectivity:bool ->
  ?clip_attribute:string ->
  ?distance:float ->
  ?selection:selection ->
  ?replace_existing_groups:bool ->
  ?clipped_edge_group:string ->
  ?cap_group:string ->
  ?clipped_group:string ->
  ?above_group:string ->
  ?below_group:string ->
  ?local_normal:Prismel_math.Vec3.t ->
  transform:Prismel_math.Mat4.t ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result
