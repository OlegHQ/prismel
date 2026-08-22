module C = Configurator.V1

let () =
  C.main ~name:"runtime" (fun config ->
    let flags =
      match C.ocaml_config_var config "system" with
      | Some "macosx" -> ["-Wl,-no_warn_duplicate_libraries"]
      | _ -> []
    in
    C.Flags.write_sexp "c_library_flags.sexp" flags)
