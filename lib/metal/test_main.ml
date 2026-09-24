let tests = [
  "test_metal_argument_reflection_snapshot", Test_metal_argument_reflection_snapshot.run;
  "test_metal_presentation_safe", Test_metal_presentation_safe.run;
  "test_metal_presentation_10k", Test_metal_presentation_10k.run;
  "test_metal_m1_ray_query", Test_metal_m1_ray_query.run;
  "test_metal_resource100_safe", Test_metal_resource100_safe.run;
  "test_metal_resource_bounds", Test_metal_resource_bounds.run;
  "test_metal_tensor47_safe", Test_metal_tensor47_safe.run;
  "test_metal_pipeline113_safe", Test_metal_pipeline113_safe.run;
  "test_metal_shader157_safe", Test_metal_shader157_safe.run;
  "test_metal_library42_safe", Test_metal_library42_safe.run;
  "test_metal_blit_command25_safe", Test_metal_blit_command25_safe.run;
  "test_metal_io_compressor_safe", Test_metal_io_compressor_safe.run;
  "test_metal_mesh_tile105_safe", Test_metal_mesh_tile105_safe.run;
  "test_metal_command_events_safe", Test_metal_command_events_safe.run;
  "test_metal_command_support121_safe", Test_metal_command_support121_safe.run;
  "test_metal_io_safe", Test_metal_io_safe.run;
  "test_metal_log_state7_safe", Test_metal_log_state7_safe.run;
  "test_metal_function_constant_values3_safe", Test_metal_function_constant_values3_safe.run;
  "test_metal4_callable_safe", Test_metal4_callable_safe.run;
  "test_metal4_render_pass7_safe", Test_metal4_render_pass7_safe.run;
  "test_metal4_msaa_render_safe", Test_metal4_msaa_render_safe.run;
  "test_metal4_command_buffer7_safe", Test_metal4_command_buffer7_safe.run;
  "test_metal4_command_queue6_safe", Test_metal4_command_queue6_safe.run;
  "test_metal4_argument_table1_safe", Test_metal4_argument_table1_safe.run;
  "test_metal4_render_pipeline_reset2_safe", Test_metal4_render_pipeline_reset2_safe.run;
  "test_metal4_compute_pipeline_reset1_safe", Test_metal4_compute_pipeline_reset1_safe.run;
  "test_metal4_command_encoder_wait_fence_safe", Test_metal4_command_encoder_wait_fence_safe.run;
  "test_metal_device_library5_safe", Test_metal_device_library5_safe.run;
  "test_metal_device_queues3_safe", Test_metal_device_queues3_safe.run;
  "test_metal_device_io2_safe", Test_metal_device_io2_safe.run;
  "test_render_pipeline93_descriptor_safe", Test_render_pipeline93_descriptor_safe.run;
  "test_render_pipeline93_mesh_graph_safe", Test_render_pipeline93_mesh_graph_safe.run;
  "test_render_pipeline93_tile_graph_safe", Test_render_pipeline93_tile_graph_safe.run;
  "test_render_pipeline93_arrays_safe", Test_render_pipeline93_arrays_safe.run;
  "test_metal4_acceleration_structure11_safe", Test_metal4_acceleration_structure11_safe.run;
  "test_metal_acceleration_safe", Test_metal_acceleration_safe.run;
  "test_metal_function_tables_safe", Test_metal_function_tables_safe.run;
  "test_device_generated_capabilities", Test_device_generated_capabilities.run;
  "test_metal_stress", Test_metal_stress.run;
  "test_metal_icb", Test_metal_icb.run;
  "test_metal_render_encoder_safe", Test_metal_render_encoder_safe.run;
  "test_metal_capture_manager_safe", Test_metal_capture_manager_safe.run;
  "test_metal_compute_pass_safe", Test_metal_compute_pass_safe.run;
  "test_metal_compute_encoder35_safe", Test_metal_compute_encoder35_safe.run;
  "test_metal_linked_functions_safe", Test_metal_linked_functions_safe.run;
  "test_metal_stage_input_output_safe", Test_metal_stage_input_output_safe.run;
  "test_metal_blit_pass_safe", Test_metal_blit_pass_safe.run;
  "test_metal_counters_safe", Test_metal_counters_safe.run;
  "test_metal_command_buffer19_safe", Test_metal_command_buffer19_safe.run;
  "test_metal_capture_scope11_safe", Test_metal_capture_scope11_safe.run;
  "test_metal_parallel_render7_safe", Test_metal_parallel_render7_safe.run;
  "test_metal_compute_pipeline11_safe", Test_metal_compute_pipeline11_safe.run;
  "test_metal_command_encoder9_safe", Test_metal_command_encoder9_safe.run;
  "test_metal_pipeline4_buffer_descriptor_safe", Test_metal_pipeline4_buffer_descriptor_safe.run;
  "test_metal_binary_archive5_safe", Test_metal_binary_archive5_safe.run;
  "test_metal_function_descriptor4_safe", Test_metal_function_descriptor4_safe.run;
  "test_metal_fence6_safe", Test_metal_fence6_safe.run;
  "test_metal_indirect_command_buffer4_safe", Test_metal_indirect_command_buffer4_safe.run;
  "test_metal_argument8_safe", Test_metal_argument8_safe.run;
  "test_metal_library8_safe", Test_metal_library8_safe.run;
  "test_metal_function_log_safe", Test_metal_function_log_safe.run;
  "test_metal_command_queue_safe", Test_metal_command_queue_safe.run;
]

let () =
  match Array.to_list Sys.argv with
  | _ :: name :: _ ->
      (match List.assoc_opt name tests with
       | Some run -> run ()
       | None -> failwith ("unknown test: " ^ name))
  | _ -> failwith "usage: test_main <name>"
