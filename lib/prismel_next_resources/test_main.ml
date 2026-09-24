let tests = [
  "test_prismel_next_resources", Test_prismel_next_resources.run;
  "test_prismel_next_font", Test_prismel_next_font.run;
  "test_prismel_next_audio", Test_prismel_next_audio.run;
  "test_png_rows", Test_png_rows.run;
]

let () =
  match Array.to_list Sys.argv with
  | [_; name] ->
      (match List.assoc_opt name tests with
       | Some run -> run ()
       | None -> failwith ("unknown test: " ^ name))
  | _ -> failwith "usage: test_main <name>"
