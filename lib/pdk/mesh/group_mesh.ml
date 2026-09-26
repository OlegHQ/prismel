type incidence = Edge_ops.incidence =
  | Any_edge
  | Boundary_edge
  | Manifold_edge
  | Non_manifold_edge

type angle_basis = Edge_ops.angle_basis =
  | Primitive_dihedral
  | Incident_edges

type path_mode = Group_path.mode = Through_each | Start_end_pairs
type path_ending = Group_path.ending = Stop_at_end | Close_path

let group_edges_checked ?cancel ?grain ?name ?primitives ?incidence
    ?min_length ?max_length ?angle_basis ?min_angle ?max_angle geometry =
  Error.guard ~operation:"group_edges" ~code:"invalid_edge_group" (fun () ->
    Edge_ops.group ?cancel ?grain ?name ?primitives ?incidence ?min_length
      ?max_length ?angle_basis ?min_angle ?max_angle geometry)

let group_find_path_checked ?cancel ?grain ?mode ?ending
    ?avoid_self_intersection ?collision ?contain ~base ~name geometry =
  Error.guard ~operation:"group_find_path" ~code:"invalid_group" (fun () ->
    Group_path.run ?cancel ?grain ?mode ?ending ?avoid_self_intersection
      ?collision ?contain ~base ~name geometry)
