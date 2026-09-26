type equalize_method = Edge_ops.equalize_method =
  | Equalize_average
  | Equalize_longest
  | Equalize_shortest
type relax_selection = Edge_relax.selection =
  | Relax_points of Group.t
  | Relax_primitives of Group.t
type relax_target_mode = Edge_relax.target_mode =
  | Individual_lengths
  | Scale_independent_distribution

val edge_cusp_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?edges:Edge_group.t ->
  ?update_point_normals:bool -> Geometry.t -> (Geometry.t, Error.t) result
val edge_straighten_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?edges:Edge_group.t ->
  ?output_group:string -> Geometry.t -> (Geometry.t, Error.t) result
val circle_from_edges_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?edges:Edge_group.t -> ?radius:float ->
  ?scale:Prismel_math.Vec3.t -> ?output_group:string -> Geometry.t ->
  (Geometry.t, Error.t) result
val edge_equalize_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?edges:Edge_group.t ->
  ?method_:equalize_method -> ?iterations:int -> ?tolerance:float ->
  ?output_group:string -> Geometry.t -> (Geometry.t, Error.t) result
val edge_relax_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:relax_selection ->
  ?pin_points:Group.t -> ?iterations:int -> ?step_size:float ->
  ?target_mode:relax_target_mode -> ?only_shorten:bool -> ?tolerance:float ->
  reference:Geometry.t -> Geometry.t -> (Geometry.t, Error.t) result
val edge_divide_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?edges:Edge_group.t ->
  ?divisions:int -> ?share_points:bool -> Geometry.t ->
  (Geometry.t, Error.t) result
