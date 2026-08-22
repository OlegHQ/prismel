type mode =
  | Address
  | Undefined
  | Thread
  | Leaks
  | Guard_malloc

type test =
  { label : string
  ; executable : string
  }

type process_result =
  { status : Unix.process_status
  ; stdout : string
  ; stderr : string
  }

let fail format = Printf.ksprintf failwith format

let read_file path =
  let input = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr input)
    (fun () -> really_input_string input (in_channel_length input))

let rec remove_directory path =
  Sys.readdir path
  |> Array.iter (fun name ->
    let entry = Filename.concat path name in
    if Sys.is_directory entry then remove_directory entry else Sys.remove entry);
  Unix.rmdir path

let with_temp_directory prefix callback =
  let path = Filename.temp_dir prefix "" in
  Fun.protect ~finally:(fun () -> remove_directory path) (fun () -> callback path)

let environment_name entry =
  match String.index_opt entry '=' with
  | Some index -> String.sub entry 0 index
  | None -> entry

let environment_with replacements removals =
  let replaced = List.map fst replacements @ removals in
  let inherited =
    Unix.environment ()
    |> Array.to_list
    |> List.filter (fun entry ->
      not (List.mem (environment_name entry) replaced))
  in
  Array.of_list
    (List.map (fun (name, value) -> name ^ "=" ^ value) replacements
     @ inherited)

let run ~environment program arguments =
  with_temp_directory "prismel-metal-memory-" (fun directory ->
    let stdout_path = Filename.concat directory "stdout" in
    let stderr_path = Filename.concat directory "stderr" in
    let flags = [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] in
    let stdout_fd = Unix.openfile stdout_path flags 0o600 in
    let stderr_fd = Unix.openfile stderr_path flags 0o600 in
    let pid =
      Fun.protect
        ~finally:(fun () ->
          Unix.close stdout_fd;
          Unix.close stderr_fd)
        (fun () ->
          Unix.create_process_env program
            (Array.of_list (program :: arguments)) environment Unix.stdin
            stdout_fd stderr_fd)
    in
    let _, status = Unix.waitpid [] pid in
    { status; stdout = read_file stdout_path; stderr = read_file stderr_path })

let status_string = function
  | Unix.WEXITED code -> Printf.sprintf "exit %d" code
  | Unix.WSIGNALED signal -> Printf.sprintf "signal %d" signal
  | Unix.WSTOPPED signal -> Printf.sprintf "stopped %d" signal

let contains ~needle value =
  let needle_length = String.length needle in
  let value_length = String.length value in
  let rec search index =
    index + needle_length <= value_length
    && (String.sub value index needle_length = needle || search (index + 1))
  in
  needle_length = 0 || search 0

let has_nonzero_leak_summary output =
  String.split_on_char '\n' output
  |> List.exists (fun line ->
    contains ~needle:" total leaked bytes" line
    && not (contains ~needle:" 0 total leaked bytes" line))

let reject_output mode test result =
  let output = String.lowercase_ascii (result.stdout ^ "\n" ^ result.stderr) in
  let markers =
    match mode with
    | Address -> [ "error: addresssanitizer"; "addresssanitizer: check failed" ]
    | Undefined -> [ "runtime error:"; "undefinedbehaviorsanitizer" ]
    | Thread -> [ "warning: threadsanitizer"; "threadsanitizer: reported" ]
    | Leaks -> [ "root leak"; "leak of" ]
    | Guard_malloc -> [ "guardmalloc: invalid"; "guardmalloc: error" ]
  in
  match List.find_opt (fun marker -> contains ~needle:marker output) markers with
  | Some marker ->
      fail "%s output contains %S:\n%s%s" test.label marker result.stdout
        result.stderr
  | None when mode = Leaks && has_nonzero_leak_summary output ->
      fail "%s reports leaked bytes:\n%s%s" test.label result.stdout result.stderr
  | None -> ()

let existing_executable artifacts relative =
  let path = Filename.concat artifacts relative in
  if not (Sys.file_exists path && not (Sys.is_directory path)) then
    fail "missing Metal test executable: %s" path;
  Unix.realpath path

let tests mode artifacts =
  let test label relative =
    { label; executable = existing_executable artifacts relative }
  in
  let conformance = test "Metal conformance" "lib/metal/test_metal.exe" in
  let stress =
    test "Metal 100000-cycle ownership stress"
      "lib/metal/test_metal_stress.exe"
  in
  match mode with Guard_malloc -> [ conformance ] | _ -> [ conformance; stress ]

let base_removals =
  [ "ASAN_OPTIONS"; "UBSAN_OPTIONS"; "TSAN_OPTIONS"
  ; "DYLD_INSERT_LIBRARIES"; "MallocStackLogging"
  ; "PRISMEL_METAL_STRESS_RSS_TOLERANCE"
  ]

let run_test mode test =
  let program, arguments, replacements =
    match mode with
    | Address ->
        ( test.executable
        , []
        , [ ( "ASAN_OPTIONS"
            , "abort_on_error=1:halt_on_error=1:detect_leaks=0:strict_string_checks=1:use_sigaltstack=0:quarantine_size_mb=0:thread_local_quarantine_size_kb=0" )
          ] )
    | Undefined ->
        ( test.executable
        , []
        , [ "UBSAN_OPTIONS", "halt_on_error=1:print_stacktrace=1" ] )
    | Thread ->
        ( test.executable
        , []
        , [ "TSAN_OPTIONS", "halt_on_error=1"
          ; "PRISMEL_METAL_STRESS_RSS_TOLERANCE", "67108864"
          ] )
    | Leaks ->
        "/usr/bin/leaks", [ "--quiet"; "--atExit"; "--"; test.executable ], []
    | Guard_malloc ->
        ( test.executable
        , []
        , [ "DYLD_INSERT_LIBRARIES", "/usr/lib/libgmalloc.dylib"
          ; "MallocStackLogging", "1"
          ] )
  in
  let result =
    run ~environment:(environment_with replacements base_removals) program
      arguments
  in
  (match result.status with
   | Unix.WEXITED 0 -> ()
   | status ->
       fail "%s failed with %s:\n%s%s" test.label (status_string status)
         result.stdout result.stderr);
  reject_output mode test result;
  Printf.printf "%s: passed\n%!" test.label

let parse_mode = function
  | "address" -> Address
  | "undefined" -> Undefined
  | "thread" -> Thread
  | "leaks" -> Leaks
  | "guard-malloc" -> Guard_malloc
  | value ->
      fail
        "--mode must be address, undefined, thread, leaks, or guard-malloc, not %S"
        value

let () =
  try
    let mode = ref None in
    let artifacts = ref None in
    Arg.parse
      [ "--mode", Arg.String (fun value -> mode := Some (parse_mode value)),
        "MODE memory-check mode"
      ; "--artifacts", Arg.String (fun value -> artifacts := Some value),
        "DIR Dune build context"
      ]
      (fun value -> fail "unexpected argument %S" value)
      "check_memory --mode MODE --artifacts DIR";
    let mode = match !mode with Some value -> value | None -> fail "--mode is required" in
    let artifacts =
      match !artifacts with
      | Some value -> Unix.realpath value
      | None -> fail "--artifacts is required"
    in
    if mode = Leaks && not (Sys.file_exists "/usr/bin/leaks") then
      fail "/usr/bin/leaks is unavailable";
    if mode = Guard_malloc
       && not (Sys.file_exists "/usr/lib/libgmalloc.dylib")
    then fail "Guard Malloc is unavailable";
    let tests = tests mode artifacts in
    List.iter (run_test mode) tests;
    Printf.printf "%d Metal memory checks passed\n%!" (List.length tests)
  with
  | Failure message ->
      prerr_endline message;
      exit 1
