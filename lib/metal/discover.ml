let fail format = Printf.ksprintf failwith format

let () =
  try
    match Array.to_list Sys.argv with
    | [ _; "--sanitizers"; sanitizers; "--output"; output ] ->
        let sanitizers =
          match Metal_build_config.parse_sanitizers sanitizers with
          | Ok value -> value
          | Error message -> fail "%s" message
        in
        Metal_build_config.write_sexp output
          (Metal_build_config.framework_link_flags
           @ Metal_build_config.link_flags sanitizers)
    | _ ->
        fail "usage: discover --sanitizers LIST --output FILE"
  with
  | Failure message ->
      prerr_endline message;
      exit 1
