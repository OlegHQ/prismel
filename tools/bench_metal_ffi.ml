open Metal

external benchmark_initialize : unit -> bool =
  "caml_prismel_bench_metal_initialize"

external benchmark_shutdown : unit -> unit =
  "caml_prismel_bench_metal_shutdown"

external direct_query : unit -> int64 =
  "caml_prismel_bench_metal_direct_query"

external batched_query : int -> int64 =
  "caml_prismel_bench_metal_batched_query"

external native_timed_query : int -> int64 * int64 =
  "caml_prismel_bench_metal_native_timed_query"

let fail format = Printf.ksprintf failwith format

let get = function
  | Ok value -> value
  | Error error -> fail "%s" (Format.asprintf "%a" pp_error error)

let command_output program arguments =
  let input = Unix.open_process_args_in program (Array.of_list (program :: arguments)) in
  let output = Stdlib.Buffer.create 128 in
  (try
     while true do
       Stdlib.Buffer.add_string output (input_line input);
       Stdlib.Buffer.add_char output '\n'
     done
   with End_of_file -> ());
  let status = Unix.close_process_in input in
  (match status with
   | Unix.WEXITED 0 -> ()
   | Unix.WEXITED code -> fail "%s exited %d" program code
   | Unix.WSIGNALED signal -> fail "%s was killed by signal %d" program signal
   | Unix.WSTOPPED signal -> fail "%s was stopped by signal %d" program signal);
  String.trim (Stdlib.Buffer.contents output)

let canonical_commit value =
  String.length value = 40 && String.for_all (function
    | '0'..'9' | 'a'..'f' -> true | _ -> false) value

type sample =
  { wall_seconds : float
  ; allocated_bytes : float
  ; minor_bytes : float
  ; promoted_bytes : float
  ; major_bytes : float
  ; major_collections : int
  ; checksum : int64
  ; native_nanoseconds : int64 option
  }

let gc_bytes words = words *. float_of_int (Sys.word_size / 8)

let sample operation =
  Gc.full_major ();
  let before = Gc.quick_stat () in
  let allocated_before = Gc.allocated_bytes () in
  let started = Unix.gettimeofday () in
  let checksum, native_nanoseconds = operation () in
  let wall_seconds = Unix.gettimeofday () -. started in
  let allocated_bytes = Gc.allocated_bytes () -. allocated_before in
  let after = Gc.quick_stat () in
  { wall_seconds
  ; allocated_bytes
  ; minor_bytes = gc_bytes (after.minor_words -. before.minor_words)
  ; promoted_bytes = gc_bytes (after.promoted_words -. before.promoted_words)
  ; major_bytes = gc_bytes (after.major_words -. before.major_words)
  ; major_collections = after.major_collections - before.major_collections
  ; checksum
  ; native_nanoseconds
  }

let median_by projection values =
  let sorted =
    List.sort
      (fun left right -> Float.compare (projection left) (projection right))
      values
  in
  List.nth sorted (List.length sorted / 2)

let median_float values =
  let sorted = List.sort Float.compare values in
  List.nth sorted (List.length sorted / 2)

let sample_json value =
  `Assoc
    [ "wall_seconds", `Float value.wall_seconds
    ; "allocated_bytes", `Float value.allocated_bytes
    ; "minor_bytes", `Float value.minor_bytes
    ; "promoted_bytes", `Float value.promoted_bytes
    ; "major_bytes", `Float value.major_bytes
    ; "major_collections", `Int value.major_collections
    ; "checksum", `String (Int64.to_string value.checksum)
    ; ( "native_nanoseconds"
      , match value.native_nanoseconds with
        | Some nanoseconds -> `String (Int64.to_string nanoseconds)
        | None -> `Null )
    ]

let measurement_json ~name ~iterations ~ffi_calls samples =
  let median = median_by (fun sample -> sample.wall_seconds) samples in
  `Assoc
    [ "name", `String name
    ; "iterations", `Int iterations
    ; "ffi_calls", `Int ffi_calls
    ; "sample_count", `Int (List.length samples)
    ; "median_wall_seconds", `Float median.wall_seconds
    ; "median_nanoseconds_per_iteration",
      `Float (median.wall_seconds *. 1e9 /. float_of_int iterations)
    ; "median_allocated_bytes", `Float median.allocated_bytes
    ; "median_allocated_bytes_per_iteration",
      `Float (median.allocated_bytes /. float_of_int iterations)
    ; "samples", `List (List.map sample_json samples)
    ]

let repeat count operation = List.init count (fun _ -> sample operation)

let direct_operation iterations () =
  let checksum = ref 0L in
  for index = 0 to iterations - 1 do
    checksum :=
      Int64.add !checksum
        (Int64.logxor (direct_query ()) (Int64.of_int index))
  done;
  !checksum, None

let batched_operation iterations () = batched_query iterations, None

let native_operation iterations () =
  let checksum, nanoseconds = native_timed_query iterations in
  checksum, Some nanoseconds

let safe_info_operation device iterations () =
  let checksum = ref 0L in
  for index = 0 to iterations - 1 do
    let info = get (Device.info device) in
    checksum := Int64.add !checksum (Int64.logxor info.registry_id (Int64.of_int index))
  done;
  !checksum, None

type arguments =
  { iterations : int
  ; samples : int
  ; profile : string
  ; output : string option
  ; check : bool
  }

let parse_arguments () =
  let iterations = ref 1_000_000 in
  let samples = ref 7 in
  let profile = ref "release" in
  let output = ref None in
  let check = ref false in
  let positive name raw =
    match int_of_string_opt raw with
    | Some value when value > 0 -> value
    | Some _ | None -> fail "%s must be positive, got %S" name raw
  in
  Arg.parse
    [ "--iterations", Arg.String (fun raw -> iterations := positive "iterations" raw),
      "N queries per sample"
    ; "--samples", Arg.String (fun raw -> samples := positive "samples" raw),
      "N sample count"
    ; "--profile", Arg.Set_string profile, "NAME Dune profile recorded in output"
    ; "--output", Arg.String (fun path -> output := Some path),
      "FILE write JSON instead of stdout"
    ; "--check", Arg.Set check, "validate thresholds without emitting JSON"
    ]
    (fun value -> fail "unexpected argument %S" value)
    "bench_metal_ffi [OPTIONS]";
  if !samples mod 2 = 0 then fail "--samples must be odd";
  { iterations = !iterations
  ; samples = !samples
  ; profile = !profile
  ; output = !output
  ; check = !check
  }

let write_json output value =
  match output with
  | None -> Yojson.Safe.pretty_to_channel stdout value; output_char stdout '\n'
  | Some path ->
      let channel = open_out_bin path in
      Fun.protect
        ~finally:(fun () -> close_out_noerr channel)
        (fun () ->
          Yojson.Safe.pretty_to_channel channel value;
          output_char channel '\n')

let () =
  let arguments = parse_arguments () in
  let source_commit,source_dirty =
    match arguments.output with
    |None->"",false
    |Some _->
        let commit=command_output "git" ["rev-parse";"HEAD"]in
        if not(canonical_commit commit)then
          fail"Metal FFI evidence requires a canonical Git commit, got %S"commit;
        let dirty=command_output "git" ["status";"--porcelain"]<>""in
        if dirty then fail"Metal FFI evidence refuses a dirty worktree";
        commit,dirty in
  if not (benchmark_initialize ()) then fail "Metal has no system default device";
  Fun.protect
    ~finally:benchmark_shutdown
    (fun () ->
      let device = get (Device.system_default ()) in
      Fun.protect
        ~finally:(fun () -> get (Device.destroy device))
        (fun () ->
          let info = get (Device.info device) in
          if direct_query () <> info.registry_id then
            fail "benchmark and safe binding selected different Metal devices";
          ignore (batched_query 10_000);
          ignore (native_timed_query 10_000);
          let direct =
            repeat arguments.samples (direct_operation arguments.iterations)
          in
          let batched =
            repeat arguments.samples (batched_operation arguments.iterations)
          in
          let native =
            repeat arguments.samples (native_operation arguments.iterations)
          in
          let expected = (List.hd batched).checksum in
          [ direct; batched; native ]
          |> List.iter (fun samples ->
            List.iter (fun sample ->
              if sample.checksum <> expected then
                fail "direct, batched, and native checksums differ") samples);
          let native_seconds =
            native
            |> List.filter_map (fun sample ->
              Option.map
                (fun value -> Int64.to_float value /. 1e9)
                sample.native_nanoseconds)
            |> median_float
          in
          let batch_seconds =
            (median_by (fun sample -> sample.wall_seconds) batched).wall_seconds
          in
          let overhead_ratio = batch_seconds /. native_seconds in
          if overhead_ratio > 1.05 then
            fail
              "batched FFI median %.9fs exceeds native %.9fs by %.2f%% (limit 5%%)"
              batch_seconds native_seconds ((overhead_ratio -. 1.) *. 100.);
          let safe_iterations = max 1 (arguments.iterations / 20) in
          let safe_info =
            repeat arguments.samples (safe_info_operation device safe_iterations)
          in
          let output =
            `Assoc
              [ "schema", `Int 1
              ; "benchmark", `String "metal_ffi"
              ; "source_commit", `String(if source_commit=""then
                    command_output"git"["rev-parse";"HEAD"]else source_commit)
              ; "source_dirty", `Bool source_dirty
              ; "profile", `String arguments.profile
              ; "ocaml_version", `String Sys.ocaml_version
              ; "word_size", `Int Sys.word_size
              ; "machine", `String (command_output "uname" [ "-m" ])
              ; "macos_version",
                `String (command_output "sw_vers" [ "-productVersion" ])
              ; "sdk_version", `String Provenance.sdk_version
              ; "deployment_target", `String Provenance.deployment_target
              ; "device", `String info.name
              ; "iterations", `Int arguments.iterations
              ; "sample_count", `Int arguments.samples
              ; "batch_to_native_ratio", `Float overhead_ratio
              ; "maximum_batch_to_native_ratio", `Float 1.05
              ; ( "measurements"
                , `List
                    [ measurement_json ~name:"direct_ocaml_ffi_query"
                        ~iterations:arguments.iterations
                        ~ffi_calls:arguments.iterations direct
                    ; measurement_json ~name:"batched_ocaml_ffi_query"
                        ~iterations:arguments.iterations ~ffi_calls:1 batched
                    ; measurement_json ~name:"native_objective_c_loop"
                        ~iterations:arguments.iterations ~ffi_calls:1 native
                    ; measurement_json ~name:"safe_device_info"
                        ~iterations:safe_iterations ~ffi_calls:(safe_iterations * 14)
                        safe_info
                    ] )
              ]
          in
          if arguments.check then
            Printf.printf
              "Metal FFI batching passed: %.4fx native median (limit 1.05x)\n%!"
              overhead_ratio
          else write_json arguments.output output))
