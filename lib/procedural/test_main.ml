let tests = [
  "test_procedural", Test_procedural.run;
  "test_edit_graph", Test_edit_graph.run;
  "test_procedural_parallel_exact", Test_procedural_parallel_exact.run;
  "test_dissolve_sop", Test_dissolve_sop.run;
  "test_poly_loft_sop", Test_poly_loft_sop.run;
  "test_skin_sop", Test_skin_sop.run;
  "test_poly_bridge_sop", Test_poly_bridge_sop.run;
  "test_poly_reduce_sop", Test_poly_reduce_sop.run;
  "test_remesh_sop", Test_remesh_sop.run;
  "test_convex_hull_sop", Test_convex_hull_sop.run;
  "test_extract_centroid_sop", Test_extract_centroid_sop.run;
  "test_extract_point_curve_sop", Test_extract_point_curve_sop.run;
  "test_circle_from_edges_sop", Test_circle_from_edges_sop.run;
  "test_graph_color_sop", Test_graph_color_sop.run;
  "test_measure_curvature_sop", Test_measure_curvature_sop.run;
  "test_attribute_laplacian_sop", Test_attribute_laplacian_sop.run;
  "test_triangulate2d_sop", Test_triangulate2d_sop.run;
  "test_boolean_detect_sop", Test_boolean_detect_sop.run;
  "test_boolean_sop", Test_boolean_sop.run;
  "test_intersection_analysis_sop", Test_intersection_analysis_sop.run;
  "test_poly_bevel_sop", Test_poly_bevel_sop.run;
  "test_point_split_sop", Test_point_split_sop.run;
  "test_point_generate_sop", Test_point_generate_sop.run;
  "test_point_replicate_sop", Test_point_replicate_sop.run;
  "test_ends_sop", Test_ends_sop.run;
  "test_duplicate_sop", Test_duplicate_sop.run;
  "test_transform_sop", Test_transform_sop.run;
  "test_soft_transform_sop", Test_soft_transform_sop.run;
  "test_distance_along_geometry_sop", Test_distance_along_geometry_sop.run;
  "test_distance_from_geometry_sop", Test_distance_from_geometry_sop.run;
  "test_distance_from_target_sop", Test_distance_from_target_sop.run;
  "test_sort_sop", Test_sort_sop.run;
  "test_blast_by_attribute_sop", Test_blast_by_attribute_sop.run;
  "test_crease_sop", Test_crease_sop.run;
  "test_attribute_fade_sop", Test_attribute_fade_sop.run;
  "test_attribute_mirror_sop", Test_attribute_mirror_sop.run;
  "test_rewire_vertices_sop", Test_rewire_vertices_sop.run;
  "test_poly_cut_sop", Test_poly_cut_sop.run;
  "test_separate_pieces_sop", Test_separate_pieces_sop.run;
  "test_polywire_sop", Test_polywire_sop.run;
]

let () =
  match Array.to_list Sys.argv with
  | [_; name] ->
      (match List.assoc_opt name tests with
       | Some run -> run ()
       | None -> failwith ("unknown test: " ^ name))
  | _ -> failwith "usage: test_main <name>"
