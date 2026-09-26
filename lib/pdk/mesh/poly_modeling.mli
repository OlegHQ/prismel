type bevel_shape = Poly_bevel.shape =
  | Bevel_chamfer
  | Bevel_round of { convexity : float }
type loft_minimize = Poly_loft.minimize =
  | Two_point_distance
  | Three_point_distance
type bridge_pairing = Poly_bridge.pairing =
  | Bridge_by_order
  | Bridge_by_centroid
type extrude_divide = Poly_extrude.divide =
  | Extrude_individual
  | Extrude_connected_components
type cut_element = Poly_cut.element = Poly_cut_points | Poly_cut_edges
type cut_strategy = Poly_cut.strategy = Poly_cut_remove | Poly_cut_cut
type cut_detection = Poly_cut.detection =
  | Poly_cut_all
  | Poly_cut_crossing of { attribute : string; value : float }
  | Poly_cut_change of { attribute : string; threshold : float }

val poly_bevel_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?edges:Edge_group.t ->
  ?shape:bevel_shape -> ?divisions:int -> ?point_scale_attribute:string ->
  ?ignore_flat_angle:float -> ?clamp_overlap:bool -> ?edge_group:string ->
  ?corner_group:string -> ?offset_group:string ->
  ?recompute_point_normals:bool -> distance:float -> Geometry.t ->
  (Geometry.t, Error.t) result

val poly_loft_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t -> ?rest:Geometry.t ->
  ?connect_closest_ends:bool -> ?minimize:loft_minimize -> ?u_wrap:bool ->
  ?v_wrap:bool -> ?keep_primitives:bool -> ?output_group:string ->
  ?collinearity_tolerance:float -> ?recompute_normals:bool -> Geometry.t ->
  (Geometry.t, Error.t) result

val skin_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t -> ?rest:Geometry.t ->
  ?connect_closest_ends:bool -> ?minimize:loft_minimize -> ?u_wrap:bool ->
  ?v_wrap:bool -> ?keep_primitives:bool -> ?output_group:string ->
  ?collinearity_tolerance:float -> ?recompute_normals:bool -> Geometry.t ->
  (Geometry.t, Error.t) result

val poly_bridge_checked :
  ?cancel:Cancel.t -> ?grain:int -> source:Edge_group.t ->
  destination:Edge_group.t -> ?pairing:bridge_pairing ->
  ?connect_closest_ends:bool -> ?minimize:loft_minimize ->
  ?reverse_source:bool -> ?reverse_destination:bool -> ?pairing_shift:int ->
  ?divisions:int -> ?keep_input:bool -> ?output_group:string ->
  ?collinearity_tolerance:float -> ?recompute_normals:bool -> Geometry.t ->
  (Geometry.t, Error.t) result

val poly_cut_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t ->
  ?cut_points:Group.t -> ?cut_edges:Edge_group.t -> ?element:cut_element ->
  ?strategy:cut_strategy -> ?detection:cut_detection -> ?keep_closed:bool ->
  Geometry.t -> (Geometry.t, Error.t) result

val poly_extrude_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t ->
  ?split_edges:Edge_group.t -> ?divide:extrude_divide -> ?divisions:int ->
  ?output_front:bool -> ?output_back:bool -> ?output_side:bool ->
  ?front_group:string -> ?back_group:string -> ?side_group:string ->
  ?front_boundary_group:string -> ?back_boundary_group:string ->
  distance:float -> Geometry.t -> (Geometry.t, Error.t) result
