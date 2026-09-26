type selection = Transform_ops.deform_selection =
  | Selected_points of Group.t
  | Selected_vertices of Group.t
  | Selected_primitives of Group.t
  | Selected_edges of Edge_group.t
type crease_operation = Crease.operation = Crease_add | Crease_set | Crease_delete

let rewire_vertices_checked ?cancel ?grain ?selection ?recursive
    ?delete_target_attribute ?keep_unused_points ?original_point_attribute
    ~owner ~target_attribute geometry =
  let selection = Option.map (function
    | Selected_points group -> Element_selection.Selected_points group
    | Selected_vertices group -> Element_selection.Selected_vertices group
    | Selected_primitives group -> Element_selection.Selected_primitives group
    | Selected_edges group -> Element_selection.Selected_edges group) selection in
  Error.guard ~operation:"rewire_vertices" ~code:"invalid_rewire_vertices"
    (fun () -> Rewire_vertices.run ?cancel ?grain ?selection ?recursive
      ?delete_target_attribute ?keep_unused_points ?original_point_attribute
      ~owner ~target_attribute geometry)

let mirror_checked ?cancel ?grain ?keep_original ~origin ~normal geometry =
  Error.guard ~operation:"mirror" ~code:"invalid_parameter" (fun () ->
    Mirror_geometry.run ?cancel ?grain ?keep_original ~origin ~normal geometry)

let crease_checked ?cancel ?grain ?edges ?operation ?weight ?add_vertex_color
    geometry =
  Error.guard ~operation:"crease" ~code:"invalid_crease" (fun () ->
    Crease.crease ?cancel ?grain ?edges ?operation ?weight ?add_vertex_color
      geometry)

let convex_hull_checked ?cancel ?grain ?selection ?preserve_point_payload
    ?source_point_attribute ?hull_group geometry =
  Error.guard ~operation:"convex_hull" ~code:"invalid_geometry" (fun () ->
    Convex_hull.run ?cancel ?grain ?selection ?preserve_point_payload
      ?source_point_attribute ?hull_group geometry)
