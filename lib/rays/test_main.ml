let tests = [
  "test_scene_rounded_cache", Test_scene_rounded_cache.run;
  "test_automatic_text_cache", Test_automatic_text_cache.run;
  "test_scene3_float32", Test_scene3_float32.run;
  "test_scene_display_list", Test_scene_display_list.run;
  "test_ink", Test_ink.run;
  "test_canvas_native", Test_canvas_native.run;
  "test_world", Test_world.run;
]

let () =
  match Array.to_list Sys.argv with
  | _ :: name :: _ ->
      (match List.assoc_opt name tests with
       | Some run -> run ()
       | None -> failwith ("unknown test: " ^ name))
  | _ -> failwith "usage: test_main <name>"
