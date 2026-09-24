let tests = [
  "test_ogpu_metal_foundation", Test_ogpu_metal_foundation.run;
  "test_ogpu_metal_texture", Test_ogpu_metal_texture.run;
  "test_ogpu_metal_submission", Test_ogpu_metal_submission.run;
  "test_ogpu_metal_pipeline", Test_ogpu_metal_pipeline.run;
  "test_ogpu_metal_surface", Test_ogpu_metal_surface.run;
  "test_ogpu_metal_native_pass", Test_ogpu_metal_native_pass.run;
  "test_ogpu_metal_sync", Test_ogpu_metal_sync.run;
  "test_ogpu_metal_memory", Test_ogpu_metal_memory.run;
  "test_ogpu_metal_acceleration", Test_ogpu_metal_acceleration.run;
  "test_ogpu_metal_diagnostics", Test_ogpu_metal_diagnostics.run;
  "test_ogpu_metal_capabilities", Test_ogpu_metal_capabilities.run;
  "test_ogpu_metal_render_pass", Test_ogpu_metal_render_pass.run;
  "test_ogpu_metal_portable_passes", Test_ogpu_metal_portable_passes.run;
  "test_ogpu_metal_backend", Test_ogpu_metal_backend.run;
  "test_ogpu_metal_sampler_pixels", Test_ogpu_metal_sampler_pixels.run;
  "test_scene_execution_metal", Test_scene_execution_metal.run;
  "test_pipeline_argument_buffer", Test_pipeline_argument_buffer.run;
]

let () =
  match Array.to_list Sys.argv with
  | [_; name] ->
      (match List.assoc_opt name tests with
       | Some run -> run ()
       | None -> failwith ("unknown test: " ^ name))
  | _ -> failwith "usage: test_main <name>"
