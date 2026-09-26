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

let poly_bevel_checked ?cancel ?grain ?edges ?shape ?divisions
    ?point_scale_attribute ?ignore_flat_angle ?clamp_overlap ?edge_group
    ?corner_group ?offset_group ?recompute_point_normals ~distance geometry =
  Error.guard ~operation:"poly_bevel" ~code:"invalid_topology" (fun () ->
    Poly_bevel.run ?cancel ?grain ?edges ?shape ?divisions
      ?point_scale_attribute ?ignore_flat_angle ?clamp_overlap ?edge_group
      ?corner_group ?offset_group ?recompute_point_normals ~distance geometry)

let poly_loft_checked ?cancel ?grain ?primitives ?rest ?connect_closest_ends
    ?minimize ?u_wrap ?v_wrap ?keep_primitives ?output_group
    ?collinearity_tolerance ?recompute_normals geometry =
  Error.guard ~operation:"poly_loft" ~code:"invalid_topology" (fun () ->
    Poly_loft.run ?cancel ?grain ?primitives ?rest ?connect_closest_ends
      ?minimize ?u_wrap ?v_wrap ?keep_primitives ?output_group
      ?collinearity_tolerance ?recompute_normals geometry)

let skin_checked ?cancel ?grain ?primitives ?rest ?connect_closest_ends
    ?minimize ?u_wrap ?v_wrap ?keep_primitives ?output_group
    ?collinearity_tolerance ?recompute_normals geometry =
  Error.guard ~operation:"skin" ~code:"invalid_topology" (fun () ->
    Poly_loft.run ?cancel ?grain ?primitives ?rest ?connect_closest_ends
      ?minimize ?u_wrap ?v_wrap ?keep_primitives ?output_group
      ?collinearity_tolerance ?recompute_normals ~output:Poly_loft.Polygons
      ~operation:"skin" geometry)

let poly_bridge_checked ?cancel ?grain ~source ~destination ?pairing
    ?connect_closest_ends ?minimize ?reverse_source ?reverse_destination
    ?pairing_shift ?divisions ?keep_input ?output_group ?collinearity_tolerance
    ?recompute_normals geometry =
  Error.guard ~operation:"poly_bridge" ~code:"invalid_topology" (fun () ->
    Poly_bridge.run ?cancel ?grain ~source ~destination ?pairing
      ?connect_closest_ends ?minimize ?reverse_source ?reverse_destination
      ?pairing_shift ?divisions ?keep_input ?output_group ?collinearity_tolerance
      ?recompute_normals geometry)

let poly_cut_checked ?cancel ?grain ?primitives ?cut_points ?cut_edges ?element
    ?strategy ?detection ?keep_closed geometry =
  Error.guard ~operation:"poly_cut" ~code:"invalid_poly_cut" (fun () ->
    Poly_cut.cut ?cancel ?grain ?primitives ?cut_points ?cut_edges ?element
      ?strategy ?detection ?keep_closed geometry)

let poly_extrude_checked ?cancel ?grain ?primitives ?split_edges ?divide
    ?divisions ?output_front ?output_back ?output_side ?front_group ?back_group
    ?side_group ?front_boundary_group ?back_boundary_group ~distance geometry =
  Error.guard ~operation:"poly_extrude" ~code:"invalid_geometry" (fun () ->
    Poly_extrude.run ?cancel ?grain ?primitives ?split_edges ?divide
      ?divisions ?output_front ?output_back ?output_side ?front_group ?back_group
      ?side_group ?front_boundary_group ?back_boundary_group ~distance geometry)
