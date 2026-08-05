type tangent =
  | Average_edges
  | Central_difference
  | Previous_edge
  | Next_edge
  | Z_axis

type connectivity =
  | Points
  | Rows
  | Columns
  | Rows_and_columns
  | Quads
  | Triangles
  | Alternating_triangles
  | Reverse_triangles

val run :
  ?cancel:Cancel.t ->
  grain:int ->
  ?backbones:Group.t ->
  ?cross_sections:Group.t ->
  connectivity:connectivity ->
  tangent:tangent ->
  continuous_closed:bool ->
  transform_attributes:bool ->
  reverse_cross_sections:bool ->
  scale:float ->
  roll:float ->
  twist:float ->
  caps:bool ->
  ?cap_group:string ->
  uv_attribute:string option ->
  cross_section_prefix:string ->
  backbone:Geometry.t ->
  cross_section:Geometry.t ->
  unit ->
  (Geometry.t, string) result
