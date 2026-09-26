let tests = [
  "test_prismel", Test_prismel.run;
  "test_easy_camera2", Test_easy_camera2.run;
  "test_sop_ui", Test_sop_ui.run;
  "test_custom_sop", Test_custom_sop.run;
  "test_pxui_graph", Test_pxui_graph.run;
  "test_sketch_ui", Test_sketch_ui.run;
  "test_sop_catalog", Test_sop_catalog.run;
  "native_only_rendering", Native_only_rendering.run;
  "test_sketch_support", Test_sketch_support.run;
  "dependency_gate", Dependency_gate.run;
  "sop_render_parity", Sop_render_parity.run;
]

let () =
  match Array.to_list Sys.argv with
  | _ :: name :: _ ->
      (match List.assoc_opt name tests with
       | Some run -> run ()
       | None -> failwith ("unknown test: " ^ name))
  | _ -> failwith "usage: test_main <name>"
