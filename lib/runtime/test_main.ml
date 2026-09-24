let tests = [
  "test_runtime_next", Test_runtime_next.run;
  "test_runtime_next_visibility", Test_runtime_next_visibility.run;
  "test_runtime_next_scaling", Test_runtime_next_scaling.run;
  "test_runtime_next_scene3_lighting", Test_runtime_next_scene3_lighting.run;
  "test_runtime_next_scene3_instances", Test_runtime_next_scene3_instances.run;
  "test_runtime_next_scene2_argument_shader", Test_runtime_next_scene2_argument_shader.run;
  "test_runtime_next_scene2_argument", Test_runtime_next_scene2_argument.run;
  "test_runtime_next_orchestrator", Test_runtime_next_orchestrator.run;
  "test_runtime_next_input", Test_runtime_next_input.run;
]

let () =
  match Array.to_list Sys.argv with
  | [_; name] ->
      (match List.assoc_opt name tests with
       | Some run -> run ()
       | None -> failwith ("unknown test: " ^ name))
  | _ -> failwith "usage: test_main <name>"
