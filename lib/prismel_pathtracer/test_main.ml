let tests = [
  "test_pathtracer", Test_pathtracer.run;
  "test_gpu_film", Test_gpu_film.run;
]

let () =
  match Array.to_list Sys.argv with
  | [_; name] ->
      (match List.assoc_opt name tests with
       | Some run -> run ()
       | None -> failwith ("unknown test: " ^ name))
  | _ -> failwith "usage: test_main <name>"
