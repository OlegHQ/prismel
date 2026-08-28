open Support
open Yojson.Safe.Util

let tolerance = 1e-9

let require condition format =
  Printf.ksprintf (fun message -> if not condition then fail "%s" message) format

let measurement name evidence =
  evidence |> member "measurements" |> to_list
  |> List.find_opt (fun value -> value |> member "name" |> to_string = name)
  |> function
  | Some value -> value
  | None -> fail "Metal FFI evidence is missing measurement %S" name

let median values =
  let values = List.sort Float.compare values in
  List.nth values (List.length values / 2)

let validate_commit root commit =
  require (String.length commit = 40)
    "Metal FFI evidence source commit is not a full hash: %S" commit;
  let result = command ~cwd:root "git" [ "cat-file"; "-e"; commit ^ "^{commit}" ] in
  require (successful result) "Metal FFI evidence refers to missing commit %s"
    commit

let validate_measurement ~iterations ~samples ~ffi_calls value =
  require (value |> member "iterations" |> to_int = iterations)
    "measurement iteration count changed";
  require (value |> member "sample_count" |> to_int = samples)
    "measurement sample count changed";
  require (value |> member "ffi_calls" |> to_int = ffi_calls)
    "measurement FFI-call count changed";
  let rows = value |> member "samples" |> to_list in
  require (List.length rows = samples) "measurement sample rows are incomplete";
  rows
  |> List.iter (fun row ->
    require (row |> member "wall_seconds" |> to_float > 0.)
      "measurement wall time must be positive";
    require (row |> member "allocated_bytes" |> to_float >= 0.)
      "measurement allocation must be nonnegative")

let validate root evidence_path =
  let evidence = Yojson.Safe.from_file evidence_path in
  let schema = evidence |> member "schema" |> to_int in
  require (schema = 1 || schema = 2) "Metal FFI evidence schema changed";
  require (evidence |> member "benchmark" |> to_string = "metal_ffi")
    "unexpected benchmark kind";
  require (evidence |> member "profile" |> to_string = "release")
    "Metal FFI evidence was not captured in release profile";
  require (evidence |> member "device" |> to_string <> "")
    "Metal FFI evidence has no device identity";
  require (evidence |> member "sdk_version" |> to_string = "26.5")
    "Metal FFI evidence SDK version changed";
  let commit = evidence |> member "source_commit" |> to_string in
  validate_commit root commit;
  if schema >= 2 then begin
    require (not (evidence |> member "source_dirty" |> to_bool))
      "Metal FFI evidence source was dirty before measurement";
    let commit_after = evidence |> member "source_commit_after" |> to_string in
    validate_commit root commit_after;
    require (commit_after = commit)
      "Metal FFI evidence source commit changed during measurement";
    require (not (evidence |> member "source_dirty_after" |> to_bool))
      "Metal FFI evidence source was dirty after measurement"
  end;
  let iterations = evidence |> member "iterations" |> to_int in
  let samples = evidence |> member "sample_count" |> to_int in
  require (iterations >= 1_000_000)
    "Metal FFI baseline needs at least one million iterations";
  require (samples >= 5 && samples mod 2 = 1)
    "Metal FFI baseline needs an odd sample count of at least five";
  let direct = measurement "direct_ocaml_ffi_query" evidence in
  let batched = measurement "batched_ocaml_ffi_query" evidence in
  let native = measurement "native_objective_c_loop" evidence in
  let safe = measurement "safe_device_info" evidence in
  validate_measurement ~iterations ~samples ~ffi_calls:iterations direct;
  validate_measurement ~iterations ~samples ~ffi_calls:1 batched;
  validate_measurement ~iterations ~samples ~ffi_calls:1 native;
  let safe_iterations = safe |> member "iterations" |> to_int in
  validate_measurement ~iterations:safe_iterations ~samples
    ~ffi_calls:(safe_iterations * 14) safe;
  let direct_allocation =
    direct |> member "median_allocated_bytes_per_iteration" |> to_float
  in
  let batch_allocation =
    batched |> member "median_allocated_bytes_per_iteration" |> to_float
  in
  require (direct_allocation >= 16.)
    "direct FFI allocation unexpectedly fell below one boxed result";
  require (batch_allocation < 1.)
    "batched FFI allocation is not amortized below one byte per query";
  let native_seconds =
    native |> member "samples" |> to_list
    |> List.map (fun row ->
      row |> member "native_nanoseconds" |> to_string |> Int64.of_string
      |> fun nanoseconds -> Int64.to_float nanoseconds /. 1e9)
    |> median
  in
  let batch_seconds = batched |> member "median_wall_seconds" |> to_float in
  let recomputed_ratio = batch_seconds /. native_seconds in
  let recorded_ratio = evidence |> member "batch_to_native_ratio" |> to_float in
  require (Float.abs (recorded_ratio -. recomputed_ratio) <= tolerance)
    "Metal FFI ratio does not match its samples";
  let maximum =
    evidence |> member "maximum_batch_to_native_ratio" |> to_float
  in
  require (Float.abs (maximum -. 1.05) <= tolerance)
    "Metal FFI acceptance threshold changed";
  require (recorded_ratio <= maximum)
    "Metal FFI batched/native ratio %.6f exceeds %.6f" recorded_ratio maximum;
  Printf.printf
    "Metal FFI evidence passed: %.6fx native, %.3f direct and %.6f batched bytes/query\n%!"
    recorded_ratio direct_allocation batch_allocation

let () =
  try
    let root = ref "." in
    let evidence = ref None in
    Arg.parse
      [ "--root", Arg.Set_string root, "DIR repository root"
      ; "--evidence", Arg.String (fun value -> evidence := Some value),
        "FILE evidence JSON"
      ]
      (fun value -> fail "unexpected argument %S" value)
      "validate_ffi_evidence [OPTIONS]";
    let root = Unix.realpath !root in
    let evidence =
      match !evidence with
      | Some value -> value
      | None ->
          Filename.concat root
            "specification/evidence/gpu_migration/phase2_metal_ffi_baseline.json"
    in
    validate root evidence
  with
  | Error message | Failure message ->
      prerr_endline message;
      exit 1
