let tests = [
  "test_offscreen", Test_offscreen.run;
  "test_scene2_coordinates", Test_scene2_coordinates.run;
  "test_dense_scene2", Test_dense_scene2.run;
  "test_ui_pipeline", Test_ui_pipeline.run;
]

let () =
  match Array.to_list Sys.argv with
  | [_; name] ->
      (match List.assoc_opt name tests with
       | Some run -> run ()
       | None -> failwith ("unknown test: " ^ name))
  | _ -> failwith "usage: test_main <name>"
