type overlap_policy = Keep_first_overlap | Delete_overlap_pairs

val run_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?epsilon:float ->
  ?remove_degenerate:bool -> ?consolidate_distance:float ->
  ?overlaps:overlap_policy -> ?reverse_winding:bool ->
  ?remove_nan_points:bool -> ?remove_unused_points:bool ->
  ?delete_unused_groups:bool -> ?point_attributes:string ->
  ?vertex_attributes:string -> ?primitive_attributes:string ->
  ?detail_attributes:string -> ?point_groups:string ->
  ?vertex_groups:string -> ?primitive_groups:string ->
  ?edge_groups:string -> Geometry.t -> (Geometry.t, Error.t) result
