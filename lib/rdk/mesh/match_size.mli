(** Packed geometry alignment against numeric or selected geometry bounds. *)

type deform_selection = Deform.selection =
  | Selected_points of Group.t
  | Selected_vertices of Group.t
  | Selected_primitives of Group.t
  | Selected_edges of Edge_group.t

type match_size_fit =
  | Translate_only | Stretch | Contain | Cover
  | Match_x | Match_y | Match_z
  | Match_perimeter | Match_area | Match_volume

val match_axis :
  ?grain:int -> from:Rays_math.Vec3.t -> into:Rays_math.Vec3.t ->
  Geometry.t -> (Geometry.t, Error.t) result

val run :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:deform_selection ->
  ?source_selection:deform_selection -> ?target_selection:deform_selection ->
  ?fit:match_size_fit -> ?translate_axes:(bool * bool * bool) ->
  ?scale_axes:(bool * bool * bool) -> ?justify:Rays_math.Vec3.t ->
  ?target_justify:Rays_math.Vec3.t -> ?offset:Rays_math.Vec3.t ->
  ?scale:float -> ?target_center:Rays_math.Vec3.t ->
  ?target_size:Rays_math.Vec3.t -> ?target:Geometry.t -> Geometry.t ->
  (Geometry.t, Error.t) result
