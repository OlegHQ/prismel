open Support

let baseline_relative =
  "specification/evidence/gpu_migration/phase0_baseline.json"

let output_relative =
  "specification/evidence/gpu_migration/phase0_environment.json"

let sensitive_fragments = [ "serial"; "uuid"; "udid"; "hostname"; "user_name" ]

let optional_command program arguments =
  try command program arguments with
  | Unix.Unix_error (Unix.ENOENT, _, _) ->
      { status = Unix.WEXITED 127; stdout = ""; stderr = "command not found" }

let optional_output program arguments =
  let result = optional_command program arguments in
  if successful result && result.stdout <> "" then Some result.stdout else None

let sysctl name = optional_output "sysctl" [ "-n"; name ]

let option_string = function
  | Some value -> `String value
  | None -> `Null

let split_lines value =
  if value = "" then [] else String.split_on_char '\n' value

let string_lines value = `List (List.map (fun line -> `String line) (split_lines value))

let member_or_null name value = Option.value (member name value) ~default:`Null

let sw_vers () =
  let values = Hashtbl.create 4 in
  command_output "sw_vers" [] |> split_lines
  |> List.iter (fun line ->
    match String.index_opt line ':' with
    | None -> ()
    | Some separator ->
        let key = String.sub line 0 separator |> String.trim in
        let value =
          String.sub line (separator + 1) (String.length line - separator - 1)
          |> String.trim
        in
        Hashtbl.replace values key value);
  let value key =
    Option.value (Hashtbl.find_opt values key) ~default:"unknown" |> fun value ->
    `String value
  in
  `Assoc
    [ "name", value "ProductName"
    ; "version", value "ProductVersion"
    ; "build", value "BuildVersion"
    ]

let safe_hardware () =
  let raw =
    command_output "system_profiler"
      [ "SPHardwareDataType"; "SPDisplaysDataType"; "-json" ]
    |> Yojson.Safe.from_string
  in
  let hardware =
    match member_list "SPHardwareDataType" raw with
    | Some (value :: _) -> value
    | Some [] | None -> `Assoc []
  in
  let graphics =
    Option.value (member_list "SPDisplaysDataType" raw) ~default:[]
    |> List.map (fun gpu ->
      let displays =
        Option.value (member_list "spdisplays_ndrvs" gpu) ~default:[]
        |> List.map (fun display ->
          `Assoc
            [ "name", member_or_null "_name" display
            ; "pixels", member_or_null "_spdisplays_pixels" display
            ; "resolution", member_or_null "_spdisplays_resolution" display
            ; "main", member_or_null "spdisplays_main" display
            ; "mirror", member_or_null "spdisplays_mirror" display
            ; "online", member_or_null "spdisplays_online" display
            ])
      in
      `Assoc
        [ "model", member_or_null "sppci_model" gpu
        ; "cores", member_or_null "sppci_cores" gpu
        ; "metal_family", member_or_null "spdisplays_mtlgpufamilysupport" gpu
        ; "bus", member_or_null "sppci_bus" gpu
        ; "displays", `List displays
        ])
  in
  `Assoc
    [ "machine_name", member_or_null "machine_name" hardware
    ; "machine_model", member_or_null "machine_model" hardware
    ; "chip", member_or_null "chip_type" hardware
    ; "physical_memory", member_or_null "physical_memory" hardware
    ; "processors", member_or_null "number_processors" hardware
    ; "logical_cpu_count", option_string (sysctl "hw.logicalcpu")
    ; "physical_cpu_count", option_string (sysctl "hw.physicalcpu")
    ; "memory_bytes", option_string (sysctl "hw.memsize")
    ; "graphics", `List graphics
    ]

let first_line value =
  match split_lines value with
  | line :: _ -> Some line
  | [] -> None

let toolchain () =
  let xcode_path = command_output "xcode-select" [ "-p" ] in
  let xcode = optional_command "xcodebuild" [ "-version" ] in
  let metal = optional_command "xcrun" [ "-f"; "metal" ] in
  let clang = command_output "clang" [ "--version" ] |> split_lines in
  let xcode_available = successful xcode && contains ~needle:"Xcode" xcode.stdout in
  `Assoc
    [ "developer_directory", `String xcode_path
    ; "full_xcode_available", `Bool xcode_available
    ; "xcode_version", if successful xcode then `String xcode.stdout else `Null
    ; ( "xcode_diagnostic"
      , if successful xcode then `Null else option_string (first_line xcode.stderr) )
    ; ( "macos_sdk_version"
      , `String
          (command_output "xcrun"
             [ "--sdk"; "macosx"; "--show-sdk-version" ]) )
    ; ( "macos_sdk_path"
      , `String
          (command_output "xcrun" [ "--sdk"; "macosx"; "--show-sdk-path" ]) )
    ; "metal_compiler_available", `Bool (successful metal)
    ; "metal_compiler_path", if successful metal then `String metal.stdout else `Null
    ; ( "metal_compiler_diagnostic"
      , if successful metal then `Null else option_string (first_line metal.stderr) )
    ; "clang", `List (List.map (fun line -> `String line) (List.filteri (fun index _ -> index < 2) clang))
    ; "deployment_floor", `String "macOS 14"
    ]

let version_command program arguments = optional_output program arguments |> option_string

let versions names value =
  `Assoc (List.map (fun name -> name, value name) names)

let software () =
  let opam_packages =
    [ "ocaml"; "dune"; "domainslib"; "ctypes"; "ctypes-foreign"; "tsdl"
    ; "tsdl-image"; "tsdl-ttf"; "tsdl-mixer"; "conf-sdl2"
    ; "conf-sdl2-image"; "conf-sdl2-ttf"; "conf-sdl2-mixer"
    ]
  in
  let pkg_names =
    [ "sdl2"; "SDL2_image"; "SDL2_ttf"; "SDL2_mixer"; "SDL2_gfx"; "sdl3"
    ; "SDL3_image"; "SDL3_ttf"; "SDL3_mixer"
    ]
  in
  let brew_names =
    [ "sdl2"; "sdl2_image"; "sdl2_ttf"; "sdl2_mixer"; "sdl2_gfx"; "sdl3"
    ; "sdl3_image"; "sdl3_ttf"; "sdl3_mixer"
    ]
  in
  `Assoc
    [ "ocaml", `String (command_output "ocamlc" [ "-version" ])
    ; "dune", `String (command_output "dune" [ "--version" ])
    ; ( "generator_runtime"
      , `String
          ("OCaml " ^ command_output "ocamlc" [ "-version" ]) )
    ; ( "opam_packages"
      , versions opam_packages (fun name ->
          version_command "opam" [ "show"; "--field=version"; name ]) )
    ; ( "pkg_config"
      , versions pkg_names (fun name ->
          version_command "pkg-config" [ "--modversion"; name ]) )
    ; ( "homebrew"
      , versions brew_names (fun name ->
          version_command "brew" [ "list"; "--versions"; name ]) )
    ]

let power_and_thermal () =
  let lines result =
    let value = if result.stdout <> "" then result.stdout else result.stderr in
    string_lines value
  in
  `Assoc
    [ "power", lines (optional_command "pmset" [ "-g"; "batt" ])
    ; "thermal", lines (optional_command "pmset" [ "-g"; "therm" ])
    ]

let iso8601_now () =
  let now = Unix.time () in
  let local = Unix.localtime now in
  let utc = Unix.gmtime now in
  let local_epoch, _ = Unix.mktime local in
  let utc_as_local, _ = Unix.mktime utc in
  let offset = int_of_float (local_epoch -. utc_as_local) in
  let sign = if offset < 0 then '-' else '+' in
  let offset = abs offset in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d%c%02d:%02d"
    (local.tm_year + 1900) (local.tm_mon + 1) local.tm_mday local.tm_hour
    local.tm_min local.tm_sec sign (offset / 3600) ((offset mod 3600) / 60)

let capture root =
  let baseline =
    read_file (Filename.concat root baseline_relative) |> Yojson.Safe.from_string
  in
  let head = command_output "git" [ "-C"; root; "rev-parse"; "HEAD" ] in
  let status =
    command_output "git" [ "-C"; root; "status"; "--porcelain=v1" ]
  in
  let logical_cpus =
    match Option.bind (sysctl "hw.logicalcpu") int_of_string_opt with
    | Some value -> value
    | None -> 1
  in
  `Assoc
    [ "schema", `Int 1
    ; "kind", `String "phase0_environment"
    ; "baseline_commit", member_exn "baseline_commit" baseline
    ; "capture_commit", `String head
    ; "capture_dirty", `Bool (status <> "")
    ; "local_modifications", string_lines status
    ; "captured_at", `String (iso8601_now ())
    ; "operating_system", sw_vers ()
    ; "architecture", `String (command_output "uname" [ "-m" ])
    ; "hardware", safe_hardware ()
    ; "toolchain", toolchain ()
    ; "software", software ()
    ; "power_and_thermal", power_and_thermal ()
    ; ( "benchmark_policy"
      , `Assoc
          [ "compiler_profile", `String "release"
          ; "warm_samples_per_scenario", `Int 5
          ; "interactive_sample_seconds", `Int 30
          ; "domain_counts", `List [ `Int 1; `Int logical_cpus ]
          ; ( "display_scale"
            , `String "1x external 1920x1080 baseline display" )
          ] )
    ; ( "render_target_environment"
      , `Assoc
          [ ( "captured_default"
            , option_string (Sys.getenv_opt "PRISMEL_RENDER_TARGET") )
          ; "baseline_commands_override_target_explicitly", `Bool true
          ] )
    ]

let rec sensitive_paths ?(path = "$") value =
  match value with
  | `Assoc fields ->
      List.concat_map
        (fun (key, child) ->
          let child_path = path ^ "." ^ key in
          let lowered = String.lowercase_ascii key in
          let own =
            if List.exists (fun fragment -> contains ~needle:fragment lowered)
                 sensitive_fragments
            then [ child_path ]
            else []
          in
          own @ sensitive_paths ~path:child_path child)
        fields
  | `List values ->
      List.mapi
        (fun index child ->
          sensitive_paths ~path:(Printf.sprintf "%s[%d]" path index) child)
        values
      |> List.concat
  | `Null | `Bool _ | `Int _ | `Intlit _ | `Float _ | `String _ | `Tuple _
  | `Variant _ -> []

let nonempty_string name value =
  match member_string name value with
  | Some value -> value <> ""
  | None -> false

let validate root value =
  let failures = ref [] in
  let reject condition message = if condition then failures := message :: !failures in
  let baseline =
    read_file (Filename.concat root baseline_relative) |> Yojson.Safe.from_string
  in
  reject (member_int "schema" value <> Some 1)
    "unsupported environment evidence schema";
  reject
    (member "baseline_commit" value <> member "baseline_commit" baseline)
    "environment evidence names the wrong baseline commit";
  reject (member_bool "capture_dirty" value = Some true)
    "environment evidence was captured from a dirty worktree";
  let hardware = member_exn "hardware" value in
  reject
    (not (nonempty_string "machine_model" hardware)
     || Option.value (member_list "graphics" hardware) ~default:[] = [])
    "hardware model or GPU/display facts are missing";
  let toolchain = member_exn "toolchain" value in
  reject (not (nonempty_string "macos_sdk_version" toolchain))
    "macOS SDK version is missing";
  let software = member_exn "software" value in
  reject
    (not (nonempty_string "ocaml" software && nonempty_string "dune" software))
    "OCaml or Dune version is missing";
  let policy = member_exn "benchmark_policy" value in
  reject (member_int "warm_samples_per_scenario" policy <> Some 5)
    "baseline policy must retain five samples per scenario";
  sensitive_paths value
  |> List.iter (fun path ->
    failures := ("sensitive machine identity key present at " ^ path) :: !failures);
  List.rev !failures

let main () =
  let root, mode = root_and_mode () in
  let output_path = Filename.concat root output_relative in
  match mode with
  | Write ->
      let value = capture root in
      let failures = validate root value in
      if failures <> [] then fail "%s" (String.concat "; " failures);
      ensure_directory (Filename.dirname output_path);
      write_file output_path (pretty_json value);
      Printf.printf "wrote sanitized environment evidence to %s\n%!" output_path
  | Check ->
      if not (Sys.file_exists output_path) then
        fail "missing environment evidence: %s" output_path;
      let value = read_file output_path |> Yojson.Safe.from_string in
      let failures = validate root value in
      if failures <> [] then begin
        List.iter prerr_endline failures;
        exit 1
      end;
      print_endline "Phase 0 environment evidence is complete and sanitized"

let () = protect_main main
