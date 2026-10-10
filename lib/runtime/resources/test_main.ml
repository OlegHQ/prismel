let tests = [
  "test_resources_font", Test_resources_font.run;
]

let () =
  match Array.to_list Sys.argv with
  | [_; name] ->
      (match List.assoc_opt name tests with
       | Some run -> run ()
       | None -> failwith ("unknown test: " ^ name))
  | _ -> failwith "usage: test_main <name>"
