let tests = [
  "test_ogpu_foundation", Test_ogpu_foundation.run;
  "test_ogpu_command", Test_ogpu_command.run;
  "test_ogpu_mock", Test_ogpu_mock.run;
  "test_ogpu_shader", Test_ogpu_shader.run;
  "test_ogpu_backend", Test_ogpu_backend.run;
  "test_ogpu_surface", Test_ogpu_surface.run;
  "test_ogpu_binding", Test_ogpu_binding.run;
  "test_ogpu_sync", Test_ogpu_sync.run;
  "test_ogpu_pipeline", Test_ogpu_pipeline.run;
  "test_ogpu_acceleration", Test_ogpu_acceleration.run;
  "test_ogpu_cache", Test_ogpu_cache.run;
  "test_ogpu_memory", Test_ogpu_memory.run;
  "test_ogpu_render_pass", Test_ogpu_render_pass.run;
  "test_ogpu_diagnostics", Test_ogpu_diagnostics.run;
  "test_ogpu_compute_pass", Test_ogpu_compute_pass.run;
  "test_ogpu_transfer_pass", Test_ogpu_transfer_pass.run;
  "test_ogpu_validation", Test_ogpu_validation.run;
]

let () =
  match Array.to_list Sys.argv with
  | [_; name] ->
      (match List.assoc_opt name tests with
       | Some run -> run ()
       | None -> failwith ("unknown test: " ^ name))
  | _ -> failwith "usage: test_main <name>"
