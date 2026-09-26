(* Checked entry points for curve operations implemented in pdk_curve and mesh. *)

let resample_curves_checked ?cancel ?grain ?primitives ?segments
    ?maximum_segment_length ?segment_length_attribute ?segments_attribute
    ?even_last_segment ?curve_u_attribute ?curve_number_attribute
    ?distance_attribute ?tangent_attribute geometry =
  Error.guard ~operation:"resample_curves" ~code:"invalid_geometry" (fun () ->
    Resample_curves.run ?cancel ?grain ?primitives ?segments
      ?maximum_segment_length ?segment_length_attribute ?segments_attribute
      ?even_last_segment ?curve_u_attribute ?curve_number_attribute
      ?distance_attribute ?tangent_attribute geometry)

type carve_keep = Keep_inside | Keep_outside | Keep_inside_and_outside
type carve_attribute_mode = Attribute_replace | Attribute_scale

let carve_curves_checked ?cancel ?grain ?primitives ?relative_arc_length ?first
    ?last ?first_attribute ?last_attribute
    ?(attribute_mode = Attribute_replace) ?(only_at_breakpoints = false)
    ?(cut_at_all_internal_breakpoints = false) ?(keep = Keep_inside)
    ?(extract_points = false) ?divisions ?keep_original geometry =
  Error.guard ~operation:"carve_curves" ~code:"invalid_geometry" (fun () ->
    let attribute_mode = match attribute_mode with
      | Attribute_replace -> Curve_ops.Replace
      | Attribute_scale -> Curve_ops.Scale in
    if extract_points then
      Curve_ops.extract_points ?cancel ?grain ?primitives ?relative_arc_length
        ?first ?last ?first_attribute ?last_attribute ~attribute_mode
        ~only_at_breakpoints ~cut_at_all_internal_breakpoints
        ?divisions ?keep_original geometry
    else
      let mode = match keep with
        | Keep_inside -> Curve_ops.Inside
        | Keep_outside -> Curve_ops.Outside
        | Keep_inside_and_outside -> Curve_ops.Inside_and_outside in
      Curve_ops.carve ?cancel ?grain ?primitives ?relative_arc_length ?first
        ?last ?first_attribute ?last_attribute ~attribute_mode
        ~only_at_breakpoints ~cut_at_all_internal_breakpoints ?divisions ~mode
        geometry)

let sweep_circle_raw = Sweep_circle.run

let sweep_circle_checked ?cancel ?grain ?primitives ?sides ?divisions_attribute
    ?segments ?segments_attribute ?segment_scales ?segment_scales_attribute
    ?(prevent_joint_buckling = false) ?(maximum_joint_scale = 10.)
    ?maximum_joint_scale_attribute
    ?(smooth_point = true) ?smooth_attribute ?max_valence
    ?scale_attribute ?seam_offset ?seam_attribute ?segment_seam_attribute
    ?v_attribute
    ?(generate_uv = true) ?u_range ?v_range ?uv_range_attribute ?up_attribute
    ?caps ?cap_group ~radius geometry =
  Error.guard ~operation:"sweep_circle" ~code:"invalid_geometry" (fun () ->
    let grain = Option.value ~default:16_384 grain
    and sides = Option.value ~default:12 sides
    and segments = Option.value ~default:1 segments
    and seam_offset = Option.value ~default:0 seam_offset
    and caps = Option.value ~default:false caps in
    if Option.is_none primitives && Option.is_none divisions_attribute
        && segments = 1 && Option.is_none segments_attribute
        && Option.is_none segment_scales
        && Option.is_none segment_scales_attribute
        && not prevent_joint_buckling
        && Float.is_finite maximum_joint_scale && maximum_joint_scale >= 1.
        && Option.is_none maximum_joint_scale_attribute && generate_uv
        && smooth_point && Option.is_none smooth_attribute
        && Option.is_none max_valence
        && Option.is_none segment_seam_attribute
        && Option.is_none u_range && Option.is_none v_range
        && Option.is_none uv_range_attribute then
      sweep_circle_raw ?cancel ~grain ~sides ?scale_attribute ~seam_offset
        ?seam_attribute ?v_attribute ?up_attribute ~caps ?cap_group ~radius
        geometry
    else Polywire.run ?cancel ~grain ~primitives ~sides ~divisions_attribute
        ~segments ~segments_attribute ~segment_scales
        ~segment_scales_attribute ~prevent_joint_buckling
        ~maximum_joint_scale ~maximum_joint_scale_attribute ~scale_attribute
        ~smooth_point ~smooth_attribute ~max_valence ~seam_offset
        ~seam_attribute ~segment_seam_attribute ~v_attribute ~generate_uv
        ~u_range ~v_range ~uv_range_attribute ~up_attribute ~caps ?cap_group
        ~radius geometry)
