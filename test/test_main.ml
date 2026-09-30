let tests = [
  "test_prismel", Test_prismel.run;
  "test_easy_camera2", Test_easy_camera2.run;
  "test_sop_ui", Test_sop_ui.run;
  "test_custom_sop", Test_custom_sop.run;
  "test_pxui_graph", Test_pxui_graph.run_menu;
  "test_pxui_graph_scope", Test_pxui_graph.run_scope;
  "bench_scope_pane", Test_pxui_graph.bench_scope_pane;
  "test_prismel_editor", Test_prismel_editor.run;
  "test_prismel_editor_logic", Test_prismel_editor.run_logic;
  "test_editor_document", Test_editor_document.run;
  "test_editor_input", Test_editor_input.run;
  "test_editor_commands", Test_editor_commands.run;
  "test_editor_cook", Test_editor_cook.run;
  "test_editor_transactions", Test_editor_transactions.run;
  "test_scene_tree", Test_scene_tree.run;
  "test_sop_catalog", Test_sop_catalog.run;
  "test_sketch_support", Test_sketch_support.run;
  "test_terminal_boolean_normals", Test_terminal_boolean_normals.run;
  "test_workspace_cook", Test_workspace_cook.run;
  "test_workspace_zone", Test_workspace_zone.run;
  "bench_workspace_zone", Test_workspace_zone.bench;
  "test_workspace_live", Test_workspace_live.run;
  "test_workspace_edit", Test_workspace_edit.run;
  "test_projection", Test_projection.run;
  "test_text_pane", Test_text_pane.run;
  "test_probe", Test_probe.run;
  "test_viewport_pick", Test_viewport_pick.run;
  "bench_viewport_pick", Test_viewport_pick.bench;
  "test_workspace_doc", Test_workspace_doc.run;
  "test_workspace_shell", Test_workspace_shell.run;
  "test_workspace_shell_native", Test_workspace_shell.run_native;
  "test_workspace_source", Test_workspace_source.run;
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
