let tests = [
  "test_metal_argument_reflection_snapshot", Test_metal_argument_reflection_snapshot.run;
  "test_metal_presentation_safe", Test_metal_presentation_safe.run;
  "test_metal_presentation_10k", Test_metal_presentation_10k.run;
  "test_metal_m1_ray_query", Test_metal_m1_ray_query.run;
  "test_metal_resource100_safe", Test_metal_resource100_safe.run;
  "test_metal_resource_bounds", Test_metal_resource_bounds.run;
  "test_metal_pipeline113_safe", Test_metal_pipeline113_safe.run;
  "test_metal_shader157_safe", Test_metal_shader157_safe.run;
  "test_metal_library42_safe", Test_metal_library42_safe.run;
  "test_metal_blit_command25_safe", Test_metal_blit_command25_safe.run;
  "test_metal_mesh_tile105_safe", Test_metal_mesh_tile105_safe.run;
  "test_metal_fx_safe", Test_metal_fx_safe.run;
  "test_metal_command_events_safe", Test_metal_command_events_safe.run;
  "test_metal_command_support121_safe", Test_metal_command_support121_safe.run;
  "test_metal_function_constant_values3_safe", Test_metal_function_constant_values3_safe.run;
  "test_metal_device_library5_safe", Test_metal_device_library5_safe.run;
  "test_metal_device_queues3_safe", Test_metal_device_queues3_safe.run;
  "test_render_pipeline93_descriptor_safe", Test_render_pipeline93_descriptor_safe.run;
  "test_render_pipeline93_mesh_graph_safe", Test_render_pipeline93_mesh_graph_safe.run;
  "test_render_pipeline93_tile_graph_safe", Test_render_pipeline93_tile_graph_safe.run;
  "test_render_pipeline93_arrays_safe", Test_render_pipeline93_arrays_safe.run;
  "test_metal4_acceleration_structure11_safe", Test_metal4_acceleration_structure11_safe.run;
  "test_metal_acceleration_safe", Test_metal_acceleration_safe.run;
  "test_metal_function_tables_safe", Test_metal_function_tables_safe.run;
  "test_metal_stress", Test_metal_stress.run;
  "test_metal_icb", Test_metal_icb.run;
  "test_metal_render_encoder_safe", Test_metal_render_encoder_safe.run;
  "test_metal_compute_pass_safe", Test_metal_compute_pass_safe.run;
  "test_metal_compute_encoder35_safe", Test_metal_compute_encoder35_safe.run;
  "test_metal_linked_functions_safe", Test_metal_linked_functions_safe.run;
  "test_metal_stage_input_output_safe", Test_metal_stage_input_output_safe.run;
  "test_metal_blit_pass_safe", Test_metal_blit_pass_safe.run;
  "test_metal_counters_safe", Test_metal_counters_safe.run;
  "test_metal_command_buffer19_safe", Test_metal_command_buffer19_safe.run;
  "test_metal_compute_pipeline11_safe", Test_metal_compute_pipeline11_safe.run;
  "test_metal_pipeline4_buffer_descriptor_safe", Test_metal_pipeline4_buffer_descriptor_safe.run;
  "test_metal_binary_archive5_safe", Test_metal_binary_archive5_safe.run;
  "test_metal_function_descriptor4_safe", Test_metal_function_descriptor4_safe.run;
  "test_metal_fence6_safe", Test_metal_fence6_safe.run;
  "test_metal_indirect_command_buffer4_safe", Test_metal_indirect_command_buffer4_safe.run;
  "test_metal_argument8_safe", Test_metal_argument8_safe.run;
  "test_metal_command_queue_safe", Test_metal_command_queue_safe.run;
  "test_metal_device_value25_safe", Test_metal_device_value25_safe.run;
  "test_metal_device_capability13_safe", Test_metal_device_capability13_safe.run;
  "test_metal_device_final4_safe", Test_metal_device_final4_safe.run;
  "test_metal_device_final_constructors3_safe", Test_metal_device_final_constructors3_safe.run;
  "test_metal_device_spatial_timestamp6_safe", Test_metal_device_spatial_timestamp6_safe.run;
  "test_metal_render_icb_argument", Test_metal_render_icb_argument.run;
]

let () =
  match Array.to_list Sys.argv with
  | _ :: "--group" :: group :: _ ->
      let group = int_of_string group in
      if group < 0 || group >= 8 then invalid_arg "Metal test group must be 0..7";
      List.iteri (fun index (name, run) ->
        if index mod 8 = group
           && name <> "test_metal_presentation_10k"
           && name <> "test_metal_stress" then run ()) tests
  | _ :: name :: _ ->
      (match List.assoc_opt name tests with
       | Some run -> run ()
       | None -> failwith ("unknown test: " ^ name))
  | _ -> failwith "usage: test_main <name> | --group <0..7>"
