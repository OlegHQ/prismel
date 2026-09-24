let tests = [
  "test_prismel_next_api", Test_prismel_next_api.run;
  "test_prismel_next_api_batch_d", Test_prismel_next_api_batch_d.run;
  "test_prismel_next_api_batch_a", Test_prismel_next_api_batch_a.run;
  "test_prismel_next_api_batch_b", Test_prismel_next_api_batch_b.run;
  "test_prismel_next_api_batch_c", Test_prismel_next_api_batch_c.run;
  "test_prismel_next_api_batch_c_scene_parity", Test_prismel_next_api_batch_c_scene_parity.run;
  "test_scene_rounded_cache", Test_scene_rounded_cache.run;
  "test_automatic_text_cache", Test_automatic_text_cache.run;
  "test_prismel_next_api_batch_e", Test_prismel_next_api_batch_e.run;
  "test_scene3_native_lowering", Test_scene3_native_lowering.run;
  "test_scene_display_list", Test_scene_display_list.run;
  "test_core_interface_preservation", Test_core_interface_preservation.run;
  "test_resource_interface_preservation", Test_resource_interface_preservation.run;
  "test_canvas_native", Test_canvas_native.run;
]

let () =
  match Array.to_list Sys.argv with
  | _ :: name :: _ ->
      (match List.assoc_opt name tests with
       | Some run -> run ()
       | None -> failwith ("unknown test: " ^ name))
  | _ -> failwith "usage: test_main <name>"
