module C = Configurator.V1

let () =
  C.main ~name:"tsdl_gfx" (fun config ->
    let default_libs = ["-lSDL2_gfx"] in
    let remove_tsdl_libraries = function
      | "-lSDL2" | "-lSDL2main" -> false
      | _ -> true
    in
    let cflags, libs =
      match C.Pkg_config.get config with
      | None -> [], default_libs
      | Some pkg_config ->
          (match C.Pkg_config.query pkg_config ~package:"SDL2_gfx" with
           | None -> [], default_libs
           | Some package ->
               package.cflags, List.filter remove_tsdl_libraries package.libs)
    in
    let libs =
      match C.ocaml_config_var config "system" with
      | Some "macosx" -> "-Wl,-no_warn_duplicate_libraries" :: libs
      | _ -> libs
    in
    C.Flags.write_sexp "c_flags.sexp" cflags;
    C.Flags.write_sexp "c_library_flags.sexp" libs)
