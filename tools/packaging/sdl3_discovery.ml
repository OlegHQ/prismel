module C = Configurator.V1

type component =
  | Core
  | Image
  | Ttf
  | Mixer

type link_mode =
  | Dynamic
  | Static

type details =
  { configurator_name : string
  ; package : string
  ; library : string
  ; environment_prefix : string
  ; inherits_core : bool
  }

let details = function
  | Core ->
      { configurator_name = "sdl3"
      ; package = "sdl3"
      ; library = "SDL3"
      ; environment_prefix = "PRISMEL_SDL3"
      ; inherits_core = false
      }
  | Image ->
      { configurator_name = "sdl3_image"
      ; package = "sdl3-image"
      ; library = "SDL3_image"
      ; environment_prefix = "PRISMEL_SDL3_IMAGE"
      ; inherits_core = true
      }
  | Ttf ->
      { configurator_name = "sdl3_ttf"
      ; package = "sdl3-ttf"
      ; library = "SDL3_ttf"
      ; environment_prefix = "PRISMEL_SDL3_TTF"
      ; inherits_core = true
      }
  | Mixer ->
      { configurator_name = "sdl3_mixer"
      ; package = "sdl3-mixer"
      ; library = "SDL3_mixer"
      ; environment_prefix = "PRISMEL_SDL3_MIXER"
      ; inherits_core = true
      }

let environment name =
  match Sys.getenv_opt name with
  | Some value when String.trim value <> "" -> Some (String.trim value)
  | Some _ | None -> None

let link_mode () =
  match environment "PRISMEL_SDL3_LINK_MODE" with
  | None | Some "dynamic" -> Dynamic
  | Some "static" -> Static
  | Some value ->
      C.die
        "PRISMEL_SDL3_LINK_MODE must be dynamic or static, not %S" value

let starts_with ~prefix value =
  let prefix_length = String.length prefix in
  String.length value >= prefix_length
  && String.sub value 0 prefix_length = prefix

let words value = C.Flags.extract_blank_separated_words value

let prepare_static_pkg_config config =
  let arguments =
    match Sys.getenv_opt "PKG_CONFIG_ARGN" with
    | Some value -> words value
    | None ->
        if Option.is_some (Sys.getenv_opt "PKG_CONFIG")
           || Option.is_none (C.which config "pkgconf")
        then []
        else
          match C.ocaml_config_var config "target" with
          | Some target -> [ "--personality"; target ]
          | None -> []
  in
  let arguments =
    if List.mem "--static" arguments then arguments else arguments @ [ "--static" ]
  in
  Unix.putenv "PKG_CONFIG_ARGN" (String.concat " " arguments)

let package_queries config mode details =
  (match mode with
   | Dynamic -> ()
   | Static -> prepare_static_pkg_config config);
  match C.Pkg_config.get config with
  | None -> None, None
  | Some pkg_config ->
      let package = C.Pkg_config.query pkg_config ~package:details.package in
      let core =
        if details.inherits_core
        then C.Pkg_config.query pkg_config ~package:"sdl3"
        else None
      in
      package, core

let existing_directory variable =
  match environment variable with
  | None -> None
  | Some path ->
      if not (Sys.file_exists path && Sys.is_directory path)
      then C.die "%s does not name a directory: %s" variable path;
      Some (Unix.realpath path)

let remove_inherited ~inherited flags =
  List.filter (fun flag -> not (List.mem flag inherited)) flags

let library_directories flags =
  List.filter_map
    (fun flag ->
      if starts_with ~prefix:"-L" flag && String.length flag > 2
      then Some (String.sub flag 2 (String.length flag - 2))
      else None)
    flags

let archive_name library = "lib" ^ library ^ ".a"

let find_archive details ?override_directory flags =
  let directories =
    match override_directory with
    | Some directory -> [ directory ]
    | None -> library_directories flags
  in
  let candidates =
    List.map (fun directory -> Filename.concat directory (archive_name details.library))
      directories
  in
  match List.find_opt Sys.file_exists candidates with
  | Some path -> Unix.realpath path
  | None ->
      let searched =
        match candidates with
        | [] -> "no pkg-config -L directories"
        | _ -> String.concat ", " candidates
      in
      C.die
        "static %s discovery requires %s (%s)" details.package
        (archive_name details.library) searched

let replace_library_flag details archive flags =
  let target = "-l" ^ details.library in
  let replaced = ref false in
  let flags =
    List.map
      (fun flag ->
        if flag = target
        then (
          replaced := true;
          archive)
        else flag)
      flags
  in
  if !replaced then flags else archive :: flags

let component_cflags details package =
  let override =
    existing_directory (details.environment_prefix ^ "_INCLUDE_DIR")
  in
  match override, package with
  | None, Some package -> package.C.Pkg_config.cflags
  | None, None -> []
  | Some directory, None -> [ "-I" ^ directory ]
  | Some directory, Some package ->
      ("-I" ^ directory) :: package.C.Pkg_config.cflags

let dynamic_libraries details package core override_directory =
  match override_directory, package with
  | Some directory, _ -> [ "-L" ^ directory; "-l" ^ details.library ]
  | None, Some package ->
      let inherited =
        match core with
        | Some package -> package.C.Pkg_config.libs
        | None -> []
      in
      remove_inherited ~inherited package.C.Pkg_config.libs
  | None, None -> [ "-l" ^ details.library ]

let static_libraries details package core override_directory =
  let package =
    match package with
    | Some package -> package
    | None ->
        C.die
          "static %s discovery requires pkg-config metadata for transitive link flags"
          details.package
  in
  let archive =
    find_archive details ?override_directory package.C.Pkg_config.libs
  in
  let libraries =
    replace_library_flag details archive package.C.Pkg_config.libs
  in
  let inherited =
    match core with
    | Some package -> package.C.Pkg_config.libs
    | None -> []
  in
  remove_inherited ~inherited libraries

let platform_libraries config libraries =
  match C.ocaml_config_var config "system" with
  | Some "macosx" -> "-Wl,-no_warn_duplicate_libraries" :: libraries
  | _ -> libraries

let configure config component =
  let details = details component in
  let mode = link_mode () in
  let package, core = package_queries config mode details in
  let cflags = component_cflags details package in
  let override_directory =
    existing_directory (details.environment_prefix ^ "_LIB_DIR")
  in
  let libraries =
    match mode with
    | Dynamic -> dynamic_libraries details package core override_directory
    | Static -> static_libraries details package core override_directory
  in
  C.Flags.write_sexp "c_flags.sexp" cflags;
  C.Flags.write_sexp "c_library_flags.sexp"
    (platform_libraries config libraries)

let main component =
  let details = details component in
  C.main ~name:details.configurator_name (fun config -> configure config component)
