let protected operation code work = Error.guard ~operation ~code work

type centroid_piece_owner = Extract_centroid.piece_owner =
  | Centroid_piece_points
  | Centroid_piece_primitives

type centroid_run_over = Extract_centroid.run_over =
  | Centroid_detail
  | Centroid_primitives
  | Centroid_pieces of {
      owner : centroid_piece_owner;
      attribute : string;
    }

type centroid_method = Extract_centroid.method_ =
  | Centroid_point_mass
  | Centroid_bounding_box
  | Centroid_convex_hull

let extract_centroid ?cancel ?grain ?run_over ?method_
    ?source_primitive_attribute ?piece_output_attribute geometry =
  protected "extract_centroid" "invalid_geometry" (fun () ->
    Extract_centroid.run ?cancel ?grain ?run_over ?method_
      ?source_primitive_attribute ?piece_output_attribute geometry)

type extract_curve_cut = Extract_point_curve.cut =
  | Extract_cut_constant of float
  | Extract_cut_primitive_attribute of string

let extract_point_from_curve ?cancel ?grain ?primitives ?cut ?point_attributes
    ?copy_primitive_attributes ?primitive_attributes ?curve_u_attribute
    ?number_cuts_attribute ?curve_number_attribute ~distance_attribute geometry =
  protected "extract_point_from_curve" "invalid_curve" (fun () ->
    Extract_point_curve.run ?cancel ?grain ?primitives ?cut ?point_attributes
      ?copy_primitive_attributes ?primitive_attributes ?curve_u_attribute
      ?number_cuts_attribute ?curve_number_attribute ~distance_attribute geometry)

let convert_line ?cancel ?grain ?edges ?(connect_path = false)
    ?(maximum_distance = 0.001)
    ?(connect_only_to_other_end_points = false)
    ?(make_isolated_loops_closed = false) ?(remove_unused_points = false)
    ?length_attribute geometry =
  protected "convert_line" "invalid_geometry" (fun () ->
    let generated = if connect_path then
        Poly_path.run ?cancel ?grain ?edges ~preserve_source_payload:false
          ~connect_end_points:true ~maximum_distance
          ~connect_only_to_other_end_points ~make_isolated_loops_closed geometry
      else Curve_ops.convert_line ?cancel ?grain ?edges ?length_attribute geometry in
    Result.bind generated (fun output ->
      let compacted = if remove_unused_points
        then Error.unguard (Compact_points.run ?cancel ?grain output) else Ok output in
      Result.bind compacted (fun output ->
        if connect_path then match length_attribute with
          | None -> Ok output
          | Some name -> Curve_ops.with_length_attribute ?cancel ?grain ~name output
        else Ok output)) )

type curve_end_mode = Open_curve | Close_curve | Unroll_curve

let curve_ends ?cancel ?grain ?primitives mode geometry =
  let mode = match mode with
    | Open_curve -> Curve_ops.Open
    | Close_curve -> Curve_ops.Close
    | Unroll_curve -> Curve_ops.Unroll in
  protected "curve_ends" "invalid_geometry" (fun () ->
    Curve_ops.ends ?cancel ?grain ?primitives mode geometry)

type ends_mode =
  | Ends_open
  | Ends_close_straight
  | Ends_unroll_shared
  | Ends_unroll_new

type curve_join_end = Curve_ops.curve_join_end =
  | Join_curve_start
  | Join_curve_end

type curve_join_pick = Curve_ops.curve_join_pick = {
  primitive : int;
  end_ : curve_join_end;
}

let ends ?cancel ?grain ?primitives mode geometry =
  let mode = match mode with
    | Ends_open -> Curve_ops.Open
    | Ends_close_straight -> Curve_ops.Close_straight
    | Ends_unroll_shared -> Curve_ops.Unroll
    | Ends_unroll_new -> Curve_ops.Unroll_new in
  protected "ends" "invalid_geometry" (fun () ->
    Curve_ops.ends ?cancel ?grain ?primitives ~allow_polygons:true mode geometry)

let join_curves ?cancel ?grain ?primitives ?picked_ends ?orient_closest
    ?connect_closest_ends ?only_connected ?group_size ?keep_originals
    ?tolerance ?wrap geometry =
  protected "join_curves" "invalid_geometry" (fun () ->
    Curve_ops.join ?cancel ?grain ?primitives ?picked_ends ?orient_closest
      ?connect_closest_ends ?only_connected ?group_size ?keep_originals
      ?tolerance ?wrap geometry)

let poly_path ?cancel ?grain ?connect_end_points ?maximum_distance
    ?connect_only_to_other_end_points ?make_isolated_loops_closed geometry =
  protected "poly_path" "invalid_geometry" (fun () ->
    Poly_path.run ?cancel ?grain ?connect_end_points ?maximum_distance
      ?connect_only_to_other_end_points ?make_isolated_loops_closed geometry)

