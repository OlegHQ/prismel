type shape = Point_replicate.shape =
  | Replicate_point
  | Replicate_box
  | Replicate_sphere
  | Replicate_disk
  | Replicate_line
  | Replicate_custom

type velocity_stretch = Point_replicate.velocity_stretch =
  | Replicate_no_velocity_stretch
  | Replicate_scaled_velocity
  | Replicate_velocity_only

let run_checked ?cancel ?(grain = 16_384) ?points ?keep_input ?seed
    ?id_attribute ?generated_group ?copy_point_attributes
    ?keep_source_attributes ?transform_attributes ?source_point_attribute
    ?source_index_attribute ?shape ?custom_shape ?center ?size ?orientation
    ?uniform_scale ?quasi_stratified ?velocity_stretch ?velocity_scale
    ?inherit_velocity ?radial_velocity ?noise_amplitude ?noise_frequency
    ?noise_offset ?noise_roughness ?noise_attenuation ?noise_turbulence
    ?noise_seed ~points_per_point ?scale_attribute geometry =
  Error.guard ~operation:"point_replicate" ~code:"invalid_geometry" (fun () ->
    Point_replicate.run ?cancel ~grain ?points ?keep_input ?seed ?id_attribute
      ?generated_group ?copy_point_attributes ?keep_source_attributes
      ?transform_attributes ?source_point_attribute ?source_index_attribute
      ?shape ?custom_shape ?center ?size ?orientation ?uniform_scale
      ?quasi_stratified ?velocity_stretch ?velocity_scale ?inherit_velocity
      ?radial_velocity ?noise_amplitude ?noise_frequency ?noise_offset
      ?noise_roughness ?noise_attenuation ?noise_turbulence ?noise_seed
      ~copy_basis:(fun source targets ->
        Instance_copy.Private.copy_to_points ?cancel ~grain ~source ~targets ())
      ~points_per_point ?scale_attribute geometry)
