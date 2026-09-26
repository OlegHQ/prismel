(** Packed box and lattice generator. *)

type box_connectivity =
    Box_triangles
  | Box_quads
  | Box_surface_points
  | Box_lattice_points
type box_normals = Box_no_normals | Box_point_normals | Box_vertex_normals
type box_rotation_order =
    Box_xyz
  | Box_xzy
  | Box_yxz
  | Box_yzx
  | Box_zxy
  | Box_zyx

val box_checked :
  ?cancel:Pdk_core.Cancel.t -> ?grain:int ->
  ?connectivity:box_connectivity -> ?consolidate_points:bool ->
  ?normals:box_normals -> ?center:Prismel_math.Vec3.t ->
  ?rotation:Prismel_math.Vec3.t -> ?rotation_order:box_rotation_order ->
  ?uniform_scale:float -> ?x_divisions:int -> ?y_divisions:int ->
  ?z_divisions:int -> ?uv_attribute:String.t -> ?face_groups:string ->
  size:Prismel_math.Vec3.t -> unit ->
  (Pdk_core.Geometry.t, Pdk_core.Error.t) result
