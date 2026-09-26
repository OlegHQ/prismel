type overlap_policy = Keep_first_overlap | Delete_overlap_pairs

let run_checked ?cancel ?(grain = 16_384) ?epsilon ?remove_degenerate
    ?consolidate_distance ?overlaps ?reverse_winding ?remove_nan_points
    ?remove_unused_points ?delete_unused_groups ?point_attributes
    ?vertex_attributes ?primitive_attributes ?detail_attributes ?point_groups
    ?vertex_groups ?primitive_groups ?edge_groups geometry =
  Error.guard ~operation:"clean" ~code:"invalid_geometry" (fun () ->
    Clean.run ?cancel ~grain ?epsilon ?remove_degenerate
      ?consolidate_distance
      ?overlaps:(Option.map (fun policy -> policy = Delete_overlap_pairs) overlaps)
      ?reverse_winding ?remove_nan_points ?remove_unused_points
      ?delete_unused_groups ?point_attributes ?vertex_attributes
      ?primitive_attributes ?detail_attributes ?point_groups ?vertex_groups
      ?primitive_groups ?edge_groups
      ~consolidate:(fun tolerance geometry ->
        Fuse_grid.fuse ?cancel ~grain ~tolerance geometry)
      ~compact:(fun geometry -> Compact_points.run ?cancel ~grain geometry)
      geometry)
