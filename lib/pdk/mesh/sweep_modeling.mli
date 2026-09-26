(** Checked profile revolve and sweep operations. *)

type grid_connectivity = Plane_generators.grid_connectivity =
  | Grid_points | Grid_rows | Grid_columns | Grid_rows_and_columns
  | Grid_quads | Grid_triangles | Grid_alternating_triangles
  | Grid_reverse_triangles

type revolve_type = Revolve.revolve_type = Revolve_closed | Revolve_open_arc

type sweep_tangent =
  | Sweep_average_edges
  | Sweep_central_difference
  | Sweep_previous_edge
  | Sweep_next_edge
  | Sweep_z_axis

val revolve :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  ?revolve_type:revolve_type ->
  ?connectivity:grid_connectivity ->
  ?start_angle:float ->
  ?end_angle:float ->
  ?reverse_cross_sections:bool ->
  ?caps:bool ->
  ?cap_group:string ->
  ?uv_attribute:string option ->
  divisions:int ->
  origin:Prismel_math.Vec3.t ->
  axis:Prismel_math.Vec3.t ->
  Geometry.t ->
  (Geometry.t, Error.t) result
val sweep :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?backbones:Group.t ->
  ?cross_sections:Group.t ->
  ?connectivity:grid_connectivity ->
  ?tangent:sweep_tangent ->
  ?continuous_closed:bool ->
  ?transform_attributes:bool ->
  ?reverse_cross_sections:bool ->
  ?scale:float ->
  ?roll:float ->
  ?twist:float ->
  ?caps:bool ->
  ?cap_group:string ->
  ?uv_attribute:string option ->
  ?cross_section_prefix:string ->
  backbone:Geometry.t ->
  cross_section:Geometry.t ->
  unit ->
  (Geometry.t, Error.t) result
