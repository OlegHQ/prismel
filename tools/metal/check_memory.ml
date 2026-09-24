open Check_memory_rules

type test =
  { label : string
  ; executable : string
  ; arguments : string list
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

let leak_summary output =
  String.split_on_char '\n' output
  |> List.find_map (fun line ->
    try Some (Scanf.sscanf (String.trim line)
      "Process %s %d leaks for %d total leaked bytes." (fun _ leaks bytes -> leaks,bytes))
    with Scanf.Scan_failure _ | End_of_file -> None)

let starts_with prefix value =
  String.length value >= String.length prefix
  && String.sub value 0 (String.length prefix) = prefix

let displayed_bytes line =
  let left=String.index_opt line '('and right=String.index_opt line ')'in
  match left,right with None,_|_,None->None|Some left,Some right when right<=left->None
  |Some left,Some right->
  let value=String.sub line(left+1)(right-left-1)|>String.trim in
  try
    if value.[String.length value-1]='K'then
      Some(int_of_float(float_of_string(String.sub value 0(String.length value-1))*.1024.))
    else Scanf.sscanf value"%d bytes"(fun bytes->Some bytes)
  with Failure _|Scanf.Scan_failure _|End_of_file->None

type root_classification={name:string;kind:string;instances:int;displayed_bytes:int}
let classify_roots output =
  let pending=ref None and after_separator=ref false and roots=ref[]in
  String.split_on_char '\n' output|>List.iter(fun line->
    let trimmed=String.trim line in
    if starts_with"STACK OF "trimmed&&contains~needle:"ROOT LEAK: <"trimmed then
      (try Scanf.sscanf trimmed"STACK OF %d INSTANCES OF 'ROOT LEAK: <%[^>]>':"
        (fun count name->pending:=Some(count,name))with Scanf.Scan_failure _|End_of_file->
       try Scanf.sscanf trimmed"STACK OF %d INSTANCE OF 'ROOT LEAK: <%[^>]>':"
        (fun count name->pending:=Some(count,name))with Scanf.Scan_failure _|End_of_file->pending:=Some(0,"<unparsed>"))
    else if trimmed="===="&&Option.is_some!pending then after_separator:=true
    else if!after_separator&&trimmed<>""then begin
      after_separator:=false;
      match !pending with
      |Some(instances,name)->
          let kind=if starts_with"AGX"name||starts_with"dispatch_"name then"system/framework"
            else if contains~needle:"caml_"name then"ocaml/runtime"else"unknown"in
          roots:={name;kind;instances;displayed_bytes=Option.value(displayed_bytes trimmed)~default:(-1)}::!roots;
          pending:=None
      |None->()
    end);
  List.rev!roots

let format_roots roots =
  roots|>List.map(fun root->Printf.sprintf"%s [%s]: %d roots, displayed %d bytes"
    root.name root.kind root.instances root.displayed_bytes)|>String.concat"\n"

let reject_output mode test result =
  let raw_output=result.stdout ^ "\n" ^ result.stderr in
  let output = String.lowercase_ascii raw_output in
  (match mode with
  |Leaks->(match leak_summary raw_output with
      |None->fail "%s has no parseable Leaks summary"test.label
      |Some(0,0)->()
      |Some(leaks,bytes)->
          let roots=classify_roots raw_output in
          if roots=[]||List.exists(fun root->root.kind="unknown"||root.displayed_bytes<0)roots then
            fail "%s reports %d leaks/%d bytes with unknown or unclassified roots:\n%s\n%s%s"
              test.label leaks bytes(format_roots roots)result.stdout result.stderr;
          fail "%s reports %d leaks/%d bytes:\n%s\n%s%s"test.label leaks bytes
            (format_roots roots)result.stdout result.stderr)
  |_->());
  let markers = diagnostic_markers mode in
  match List.find_opt (fun marker -> contains ~needle:marker output) markers with
  | Some marker ->
      fail "%s output contains %S:\n%s%s" test.label marker result.stdout
        result.stderr
  | None -> ()

let existing_executable artifacts relative =
  let path = Filename.concat artifacts relative in
  if not (Sys.file_exists path && not (Sys.is_directory path)) then
    fail "missing Metal test executable: %s" path;
  Unix.realpath path

let tests mode artifacts =
  let test ?(arguments = []) label relative =
    { label; executable = existing_executable artifacts relative; arguments }
  in
  let conformance = test "Metal conformance" "lib/metal/test_metal.exe" in
  let stress =
    test "Metal resource ownership stress" "lib/metal/test_metal_stress.exe"
  in
  match mode with
  | Guard_malloc -> [ conformance ]
  | Leaks ->
      let lanes =
        [ "buffers"; "textures-samplers"; "texture-views"; "heaps-resources"
        ; "sparse-heaps-textures"; "sparse-depth-stencil"
        ; "placement-sparse-resources"
        ; "residency-sets-resources"
        ; "buffer-backed-textures"; "shared-textures"; "io-surfaces"
        ; "external-buffers"
        ]
      in
      conformance
      :: List.map
           (fun lane ->
             test ~arguments:[ "--lane"; lane ]
               ("Metal ownership stress: " ^ lane)
               "lib/metal/test_metal_stress.exe")
           lanes
  | Address | Undefined | Address_undefined | Thread -> [ conformance; stress ]

let base_removals =
  [ "ASAN_OPTIONS"; "UBSAN_OPTIONS"; "TSAN_OPTIONS"
  ; "DYLD_INSERT_LIBRARIES"; "MallocStackLogging"
  ; "PRISMEL_METAL_STRESS_RSS_TOLERANCE"
  ; "PRISMEL_METAL_EXTERNAL_STRESS_RSS_TOLERANCE"
  ]

let run_test mode test =
  let required_runtimes = required_runtime_markers mode in
  if required_runtimes <> [] then begin
    let inspection = run ~environment:(Unix.environment ()) "/usr/bin/otool"
        [ "-L"; test.executable ] in
    (match inspection.status with
     | Unix.WEXITED 0 -> ()
     | status ->
         fail "%s instrumentation preflight failed with %s:\n%s%s" test.label
           (status_string status) inspection.stdout inspection.stderr);
    let linked = inspection.stdout ^ inspection.stderr in
    let missing = missing_runtime_markers mode linked in
    if missing <> [] then
      fail "%s is not instrumented for %s; missing linked runtime(s): %s"
        test.label (name mode) (String.concat ", " missing)
  end;
  let required_instrumentation = required_instrumentation_markers mode in
  if required_instrumentation <> [] then begin
    let inspection = run ~environment:(Unix.environment ()) "/usr/bin/nm"
        [ "-u"; test.executable ] in
    (match inspection.status with
     | Unix.WEXITED 0 -> ()
     | status ->
         fail "%s instrumentation-symbol preflight failed with %s:\n%s%s"
           test.label (status_string status) inspection.stdout inspection.stderr);
    let symbols = inspection.stdout ^ inspection.stderr in
    let missing = missing_instrumentation_markers mode symbols in
    if missing <> [] then
      fail "%s is not instrumented for %s; missing symbol family/families: %s"
        test.label (name mode) (String.concat ", " missing)
  end;
  let program, arguments, replacements =
    match mode with
    | Address ->
        ( test.executable
        , test.arguments
        , [ ( "ASAN_OPTIONS"
            , "abort_on_error=1:halt_on_error=1:detect_leaks=0:strict_string_checks=1:use_sigaltstack=0:quarantine_size_mb=0:thread_local_quarantine_size_kb=0" )
          ; "PRISMEL_METAL_STRESS_RSS_TOLERANCE", "268435456"
          ] )
    | Undefined ->
        ( test.executable
        , test.arguments
        , [ "UBSAN_OPTIONS", "halt_on_error=1:print_stacktrace=1" ] )
    | Address_undefined ->
        ( test.executable
        , test.arguments
        , [ ( "ASAN_OPTIONS"
            , "abort_on_error=1:halt_on_error=1:detect_leaks=0:strict_string_checks=1:use_sigaltstack=0:quarantine_size_mb=0:thread_local_quarantine_size_kb=0" )
          ; "UBSAN_OPTIONS", "halt_on_error=1:print_stacktrace=1"
          ; "PRISMEL_METAL_STRESS_RSS_TOLERANCE", "268435456"
          ] )
    | Thread ->
        ( test.executable
        , test.arguments
        , [ "TSAN_OPTIONS", "halt_on_error=1"
          ; "PRISMEL_METAL_STRESS_RSS_TOLERANCE", "402653184"
          ; "PRISMEL_METAL_EXTERNAL_STRESS_RSS_TOLERANCE", "402653184"
          ] )
    | Leaks ->
        ( "/usr/bin/leaks"
        , [ "--quiet"; "--atExit"; "--"; test.executable ] @ test.arguments
        , [] )
    | Guard_malloc ->
        ( test.executable
        , test.arguments
        , [ "DYLD_INSERT_LIBRARIES", "/usr/lib/libgmalloc.dylib"
          ; "MallocStackLogging", "1"
          ] )
  in
  let result =
    run ~environment:(environment_with replacements base_removals) program
      arguments
  in
  if mode=Leaks then reject_output mode test result;
  (match result.status with
   | Unix.WEXITED 0 -> ()
   | status ->
       fail "%s failed with %s:\n%s%s" test.label (status_string status)
         result.stdout result.stderr);
  if mode<>Leaks then reject_output mode test result;
  Printf.printf "%s: passed\n%!" test.label

let parse_mode value = match of_string value with
  | Ok mode -> mode
  | Error _ ->
      fail
        "--mode must be address, undefined, address-undefined, thread, leaks, or guard-malloc, not %S"
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
