module C = Configurator.V1

let environment name =
  match Sys.getenv_opt name with
  | Some value when String.trim value <> "" -> Some value
  | Some _ | None -> None

let () =
  C.main ~name:"sdl3_image" (fun config ->
    let package, core_package =
      match C.Pkg_config.get config with
      | None -> None, None
      | Some pkg_config ->
          C.Pkg_config.query pkg_config ~package:"sdl3-image",
          C.Pkg_config.query pkg_config ~package:"sdl3"
    in
    let cflags =
      match environment "PRISMEL_SDL3_IMAGE_INCLUDE_DIR", package with
      | Some directory, _ -> ["-I" ^ directory]
      | None, Some package -> package.cflags
      | None, None -> []
    in
    let libraries =
      match environment "PRISMEL_SDL3_IMAGE_LIB_DIR", package with
      | Some directory, _ -> ["-L" ^ directory; "-lSDL3_image"]
      | None, Some package ->
          let inherited = match core_package with
            | Some package -> package.libs
            | None -> [] in
          List.filter (fun flag -> not (List.mem flag inherited)) package.libs
      | None, None -> ["-lSDL3_image"]
    in
    let libraries =
      match C.ocaml_config_var config "system" with
      | Some "macosx" -> "-Wl,-no_warn_duplicate_libraries" :: libraries
      | _ -> libraries
    in
    C.Flags.write_sexp "c_flags.sexp" cflags;
    C.Flags.write_sexp "c_library_flags.sexp" libraries)
