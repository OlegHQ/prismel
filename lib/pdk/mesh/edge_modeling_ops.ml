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

let edge_cusp_checked ?cancel ?grain ?edges ?update_point_normals geometry =
  Error.guard ~operation:"edge_cusp" ~code:"invalid_topology" (fun () ->
    Facet.edge_cusp ?cancel ?grain ?edges ?update_point_normals geometry)

let edge_straighten_checked ?cancel ?grain ?edges ?output_group geometry =
  Error.guard ~operation:"edge_straighten" ~code:"invalid_geometry" (fun () ->
    Edge_ops.straighten ?cancel ?grain ?edges ?output_group geometry)

let circle_from_edges_checked ?cancel ?grain ?edges ?radius ?scale ?output_group
    geometry =
  Error.guard ~operation:"circle_from_edges" ~code:"invalid_circle" (fun () ->
    Circle_from_edges.run ?cancel ?grain ?edges ?radius ?scale ?output_group
      geometry)

let edge_equalize_checked ?cancel ?grain ?edges ?method_ ?iterations ?tolerance
    ?output_group geometry =
  Error.guard ~operation:"edge_equalize" ~code:"invalid_edge_equalize"
    (fun () -> Edge_ops.equalize ?cancel ?grain ?edges ?method_ ?iterations
      ?tolerance ?output_group geometry)

let edge_relax_checked ?cancel ?grain ?selection ?pin_points ?iterations
    ?step_size ?target_mode ?only_shorten ?tolerance ~reference geometry =
  Error.guard ~operation:"edge_relax" ~code:"invalid_edge_relax" (fun () ->
    Edge_relax.relax ?cancel ?grain ?selection ?pin_points ?iterations
      ?step_size ?target_mode ?only_shorten ?tolerance ~reference geometry)

let edge_divide_checked ?cancel ?grain ?edges ?divisions ?share_points geometry =
  Error.guard ~operation:"edge_divide" ~code:"invalid_topology" (fun () ->
    Subdivide.edge_divide ?cancel ?grain ?edges ?divisions ?share_points geometry)
