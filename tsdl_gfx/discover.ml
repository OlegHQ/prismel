module C = Configurator.V1

let () =
  C.main ~name:"tsdl_gfx" (fun config ->
    let default = ["-lSDL2_gfx"] in
    let flags =
      match C.Pkg_config.get config with
      | None -> default
      | Some pkg_config ->
          (match C.Pkg_config.query pkg_config ~package:"SDL2_gfx" with
           | None -> default
           | Some package -> package.libs)
    in
    C.Flags.write_sexp "c_library_flags.sexp" flags)
