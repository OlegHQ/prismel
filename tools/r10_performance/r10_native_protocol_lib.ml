open Yojson.Safe.Util

exception Invalid_report of string

let fail format =
  Printf.ksprintf (fun message -> raise (Invalid_report message)) format

let scenarios = [ "basic"; "pxui"; "canvas"; "scene3" ]
let visibilities = [ "visible"; "hidden" ]
let frozen_baseline_sha256 =
  "80da0d5026d45334d14b4d3225aa45ed3243e09eea3d8813ebb0f4b9e1ae3b6a"

let read_json path =
  try Yojson.Safe.from_file path with
  | Sys_error message | Yojson.Json_error message ->
      fail "could not read %s: %s" path message

let write_json path json =
  let channel = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
    Yojson.Safe.pretty_to_channel channel json;
    output_char channel '\n')

let command_output program arguments =
  let argv = Array.of_list (program :: arguments) in
  let input = Unix.open_process_args_in program argv in
  let buffer = Buffer.create 128 in
  (try
     while true do
       Buffer.add_string buffer (input_line input);
       Buffer.add_char buffer '\n'
     done
   with End_of_file -> ());
  match Unix.close_process_in input with
  | Unix.WEXITED 0 -> String.trim (Buffer.contents buffer)
  | Unix.WEXITED code -> fail "%s exited %d" program code
  | Unix.WSIGNALED signal | Unix.WSTOPPED signal ->
      fail "%s received signal %d" program signal

let sha256 path =
  match String.split_on_char ' '
          (command_output "/usr/bin/shasum" [ "-a"; "256"; path ]) with
  | digest :: _ when String.length digest = 64 -> digest
  | _ -> fail "could not hash %s" path

let canonical_commit value =
  String.length value = 40
  && String.for_all
       (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
       value

let git arguments = command_output "/usr/bin/git" arguments

let clean_commit () =
  let commit = git [ "rev-parse"; "HEAD" ] in
  if not (canonical_commit commit) then fail "git did not return a full commit";
  if git [ "status"; "--porcelain=v1"; "--untracked-files=all" ] <> "" then
    fail "qualification requires a clean source tree";
  commit

let run_command program arguments =
  let argv = Array.of_list (program :: arguments) in
  match snd (Unix.waitpid [] (Unix.create_process program argv Unix.stdin Unix.stdout Unix.stderr)) with
  | Unix.WEXITED 0 -> ()
  | Unix.WEXITED code -> fail "%s exited %d" program code
  | Unix.WSIGNALED signal | Unix.WSTOPPED signal ->
      fail "%s received signal %d" program signal

let preflight_benchmark ~profile benchmark =
  let prefix = "_build/default/" in
  if not (String.starts_with ~prefix benchmark) then
    fail "benchmark must be a Dune artifact below %s" prefix;
  let target =
    String.sub benchmark (String.length prefix)
      (String.length benchmark - String.length prefix)
  in
  run_command "dune" [ "build"; "--profile"; profile; target ];
  if not (Sys.file_exists benchmark) then
    fail "Dune did not produce benchmark: %s" benchmark

let number context = function
  | `Float value when Float.is_finite value && value >= 0. -> value
  | `Int value when value >= 0 -> float value
  | `Intlit value ->
      (try
         let value = float_of_string value in
         if Float.is_finite value && value >= 0. then value
         else fail "%s is not finite and non-negative" context
       with Failure _ -> fail "%s is not numeric" context)
  | _ -> fail "%s is not a finite non-negative number" context

let integer context json =
  let value = number context json in
  if Float.floor value <> value || value > float max_int then
    fail "%s is not an integer" context;
  int_of_float value

let string context = function
  | `String value when value <> "" -> value
  | _ -> fail "%s is not a non-empty string" context

let boolean context = function
  | `Bool value -> value
  | _ -> fail "%s is not a boolean" context

let field context name json =
  let value = member name json in
  if value = `Null then fail "%s lacks %s" context name;
  value

let percentile fraction values =
  match List.sort Float.compare values with
  | [] -> fail "cannot summarize an empty sample set"
  | sorted ->
      let count = List.length sorted in
      let index =
        max 0
          (min (count - 1)
             (int_of_float (Float.ceil (fraction *. float count)) - 1))
      in
      List.nth sorted index

type metric = Wall | Frame | Cpu | Promoted | Rss

let metric_name = function
  | Wall -> "wall"
  | Frame -> "frame"
  | Cpu -> "cpu_per_frame"
  | Promoted -> "promoted_per_frame"
  | Rss -> "peak_rss"

let metrics = [ Wall; Frame; Cpu; Promoted; Rss ]

let raw_metric context metric raw =
  let get name = number (context ^ "." ^ name) (field context name raw) in
  let frames () =
    let value = get "sample_frames" in
    if value <= 0. then fail "%s measured no frames" context;
    value
  in
  match metric with
  | Wall -> get "wall_seconds", get "wall_seconds"
  | Frame -> get "median_ms" /. 1000., get "p95_ms" /. 1000.
  | Cpu ->
      let value = (get "user_seconds" +. get "system_seconds") /. frames () in
      value, value
  | Promoted ->
      let value = get "promoted_bytes" /. frames () in
      value, value
  | Rss ->
      let value = get "peak_sampled_rss_kib" in
      value, value

let baseline_metric context metric run =
  let get name = number (context ^ "." ^ name) (field context name run) in
  let frames () =
    let value = get "frames" in
    if value <= 0. then fail "%s has no frames" context;
    value
  in
  match metric with
  | Wall -> get "wall_seconds", get "wall_seconds"
  | Frame -> get "median_frame_seconds", get "p95_frame_seconds"
  | Cpu ->
      let value = (get "user_seconds" +. get "system_seconds") /. frames () in
      value, value
  | Promoted ->
      let value = get "promoted_bytes" /. frames () in
      value, value
  | Rss ->
      let value = get "peak_sampled_rss_kib" in
      value, value

let summarize metric extract values =
  let medians, p95s = List.split (List.map (extract metric) values) in
  let median = percentile 0.5 medians in
  let p95 =
    match metric with
    | Frame -> percentile 0.5 p95s
    | Wall | Cpu | Promoted | Rss -> percentile 0.95 p95s
  in
  median, p95

let baseline_runs ~baseline_path ~profile ~width ~height scenario =
  let document = read_json baseline_path in
  let key = "renderer:native:" ^ scenario in
  let matches =
    document |> member "groups" |> to_list
    |> List.filter (fun group -> member "key" group = `String key)
  in
  let group = match matches with
    | [ group ] -> group
    | [] -> fail "frozen baseline lacks %s" key
    | _ -> fail "frozen baseline duplicates %s" key
  in
  if member "profile" group <> `String profile then
    fail "frozen baseline %s profile mismatch" key;
  let runs = member "runs" group |> to_list in
  if List.length runs <> 5 then
    fail "frozen baseline %s has %d runs, expected 5" key (List.length runs);
  List.iteri
    (fun index run ->
      let context = Printf.sprintf "%s run %d" key (index + 1) in
      if member "profile" run <> `String profile then
        fail "%s profile mismatch" context;
      if integer context (field context "width" run) <> width
         || integer context (field context "height" run) <> height
      then fail "%s resolution mismatch" context)
    runs;
  runs

let expected_raw_scenario = function
  | "basic" -> "basic"
  | "pxui" -> "pxui-like"
  | "canvas" -> "canvas-like"
  | "scene3" -> "scene3-double68"
  | scenario -> fail "unknown scenario %s" scenario

let sample_raw context sample = field context "raw" sample

let samples_for report scenario visibility =
  report |> member "samples" |> to_list
  |> List.filter (fun sample ->
       member "scenario" sample = `String scenario
       && member "visibility" sample = `String visibility)

let check_cell_semantics ~smoke ~sample_seconds ~profile ~width ~height
    scenario visibility samples =
  let signatures = ref [] and hashes = ref [] and work_units = ref [] in
  List.iteri
    (fun index sample ->
      let context =
        Printf.sprintf "%s/%s run %d" scenario visibility (index + 1)
      in
      let raw = sample_raw context sample in
      if string context (field context "profile" raw) <> profile then
        fail "%s profile mismatch" context;
      if integer context (field context "width" raw) <> width
         || integer context (field context "height" raw) <> height
      then fail "%s resolution mismatch" context;
      if string context (field context "scenario" raw)
         <> expected_raw_scenario scenario
      then fail "%s workload scenario mismatch" context;
      if string context (field context "visibility" raw) <> visibility then
        fail "%s requested visibility mismatch" context;
      if boolean context (field context "observed_visible" raw)
         <> (visibility = "visible")
      then fail "%s observed visibility mismatch" context;
      if not (boolean context (field context "semantics_supported" raw)) then
        fail "%s does not support the exact workload" context;
      let frames = integer context (field context "sample_frames" raw) in
      if frames <= 0 then fail "%s measured no frames" context;
      let wall = number context (field context "wall_seconds" raw) in
      if not smoke
         && (wall < sample_seconds *. 0.90 || wall > sample_seconds *. 1.10)
      then fail "%s wall interval %.3fs is outside the 10%% protocol envelope"
          context wall;
      List.iter (fun metric -> ignore (raw_metric context metric raw)) metrics;
      signatures := string context (field context "workload_signature" raw)
                    :: !signatures;
      hashes := string context (field context "canonical_framebuffer_digest" raw)
                :: !hashes;
      work_units := integer context (field context "work_units" raw)
                    :: !work_units;
      let authority =
        string context (field context "canonical_pixel_authority" raw)
      in
      if authority <> "r10-canonical-frame-1/" ^ scenario then
        fail "%s canonical pixel authority mismatch" context)
    samples;
  let unique compare values = List.sort_uniq compare values in
  if List.length (unique String.compare !signatures) <> 1 then
    fail "%s/%s workload signature drift" scenario visibility;
  if List.length (unique String.compare !hashes) <> 1 then
    fail "%s/%s canonical framebuffer drift" scenario visibility;
  if List.length (unique Int.compare !work_units) <> 1
     || List.hd !work_units <= 0
  then fail "%s/%s work cardinality drift" scenario visibility

let ratio value baseline =
  if baseline = 0. then if value = 0. then 1. else Float.infinity
  else value /. baseline

let validate_report report =
  if member "schema" report <> `String "prismel-r10-native/v1" then
    fail "report schema is not prismel-r10-native/v1";
  let protocol = field "report" "protocol" report in
  let profile = string "protocol.profile" (field "protocol" "profile" protocol)
  and width = integer "protocol.width" (field "protocol" "width" protocol)
  and height = integer "protocol.height" (field "protocol" "height" protocol)
  and expected = integer "protocol.samples" (field "protocol" "samples" protocol)
  and sample_seconds =
    number "protocol.sample_seconds" (field "protocol" "sample_seconds" protocol)
  and smoke = boolean "protocol.smoke" (field "protocol" "smoke" protocol) in
  if expected <> (if smoke then 1 else 5) then
    fail "protocol requires %d sample(s), got %d" (if smoke then 1 else 5) expected;
  let provenance = field "report" "provenance" report in
  let baseline_path =
    string "provenance.baseline_path"
      (field "provenance" "baseline_path" provenance)
  in
  let baseline_digest = sha256 baseline_path in
  if baseline_digest <> frozen_baseline_sha256 then
    fail "Phase0 baseline digest drift: %s" baseline_digest;
  if member "baseline_sha256" provenance <> `String frozen_baseline_sha256 then
    fail "report baseline digest provenance mismatch";
  if not smoke then begin
    let commit = string "provenance.git_commit" (field "provenance" "git_commit" provenance) in
    if not (canonical_commit commit) then fail "report lacks a canonical git commit";
    if boolean "provenance.git_dirty" (field "provenance" "git_dirty" provenance) then
      fail "qualification report was captured from a dirty source tree";
    let executable_sha =
      string "provenance.executable_sha256"
        (field "provenance" "executable_sha256" provenance)
    in
    if String.length executable_sha <> 64 then
      fail "report lacks a benchmark executable digest";
    let protocol_sha =
      string "provenance.protocol_executable_sha256"
        (field "provenance" "protocol_executable_sha256" provenance)
    in
    if String.length protocol_sha <> 64 then
      fail "report lacks a protocol executable digest"
  end;
  let summaries = ref [] in
  List.iter
    (fun scenario ->
      let baseline = baseline_runs ~baseline_path ~profile ~width ~height scenario in
      List.iter
        (fun visibility ->
          let samples = samples_for report scenario visibility in
          if List.length samples <> expected then
            fail "%s/%s has %d samples, expected %d" scenario visibility
              (List.length samples) expected;
          check_cell_semantics ~smoke ~sample_seconds ~profile ~width ~height
            scenario visibility samples;
          let checks =
            List.map
              (fun metric ->
                let candidate_median, candidate_p95 =
                  summarize metric
                    (fun metric sample ->
                       let context = scenario ^ "/" ^ visibility in
                       raw_metric context metric (sample_raw context sample))
                    samples
                and baseline_median, baseline_p95 =
                  summarize metric
                    (fun metric run -> baseline_metric scenario metric run)
                    baseline
                in
                let median_ratio = ratio candidate_median baseline_median
                and p95_ratio = ratio candidate_p95 baseline_p95 in
                if not smoke && median_ratio > 1.05 then
                  fail "%s/%s %s median regressed %.3fx (maximum 1.05x)"
                    scenario visibility (metric_name metric) median_ratio;
                if not smoke && p95_ratio > 1.10 then
                  fail "%s/%s %s p95 regressed %.3fx (maximum 1.10x)"
                    scenario visibility (metric_name metric) p95_ratio;
                `Assoc
                  [ "metric", `String (metric_name metric)
                  ; "candidate_median", `Float candidate_median
                  ; "candidate_p95", `Float candidate_p95
                  ; "baseline_median", `Float baseline_median
                  ; "baseline_p95", `Float baseline_p95
                  ; "median_ratio", `Float median_ratio
                  ; "p95_ratio", `Float p95_ratio
                  ; "passed", `Bool (smoke || (median_ratio <= 1.05 && p95_ratio <= 1.10))
                  ])
              metrics
          in
          summaries :=
            `Assoc
              [ "scenario", `String scenario
              ; "visibility", `String visibility
              ; "baseline_authority",
                  `String (baseline_path ^ "#renderer:native:" ^ scenario)
              ; "checks", `List checks
              ]
            :: !summaries)
        visibilities;
      let scenario_samples =
        List.concat_map (samples_for report scenario) visibilities
      in
      let unique_raw name convert =
        scenario_samples
        |> List.map (fun sample ->
             let context = scenario ^ " exact-work" in
             convert context (field context name (sample_raw context sample)))
        |> List.sort_uniq compare
      in
      if List.length (unique_raw "workload_signature" string) <> 1 then
        fail "%s workload signature differs between visibility lanes" scenario;
      if List.length (unique_raw "work_units" integer) <> 1 then
        fail "%s work cardinality differs between visibility lanes" scenario;
      if List.length (unique_raw "canonical_framebuffer_digest" string) <> 1 then
        fail "%s canonical framebuffer differs between visibility lanes" scenario)
    scenarios;
  let summaries = List.rev !summaries in
  (match member "summaries" report with
   | `Null -> ()
   | `List claimed when claimed = summaries -> ()
   | `List _ -> fail "stored summaries differ from independent recomputation"
   | _ -> fail "summaries must be a list");
  summaries

let capture argv =
  let output = Filename.temp_file "prismel-r10-native-" ".json"
  and errors = Filename.temp_file "prismel-r10-native-" ".stderr" in
  let output_fd = Unix.openfile output [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600
  and error_fd = Unix.openfile errors [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
  let pid = Unix.create_process argv.(0) argv Unix.stdin output_fd error_fd in
  Unix.close output_fd;
  Unix.close error_fd;
  let read_text path =
    let channel = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
      really_input_string channel (in_channel_length channel))
  in
  let cleanup () =
    (try Sys.remove output with Sys_error _ -> ());
    (try Sys.remove errors with Sys_error _ -> ())
  in
  let status = snd (Unix.waitpid [] pid) in
  match status with
  | Unix.WEXITED 0 ->
      Fun.protect ~finally:cleanup (fun () -> read_json output)
  | Unix.WEXITED code ->
      let detail = String.trim (read_text errors) in
      cleanup ();
      fail "child exited %d: %s" code detail
  | Unix.WSIGNALED signal | Unix.WSTOPPED signal ->
      let detail = String.trim (read_text errors) in
      cleanup ();
      fail "child received signal %d: %s" signal detail

let run ~benchmark ~baseline_path ~output ~profile ~width ~height ~samples
    ~warmup_seconds ~sample_seconds ~smoke ~dry_run =
  let baseline_path =
    try Unix.realpath baseline_path with Unix.Unix_error _ ->
      fail "baseline does not exist: %s" baseline_path
  in
  let runs = if smoke then 1 else samples in
  if profile <> "release" then fail "R10 qualification requires release profile";
  if width <> 640 || height <> 480 then
    fail "R10 frozen Phase0 comparison requires 640x480";
  if not smoke && runs <> 5 then fail "R10 qualification requires exactly 5 runs";
  if warmup_seconds <= 0. || sample_seconds <= 0. then
    fail "warmup and sample durations must be positive";
  if not dry_run then preflight_benchmark ~profile benchmark;
  if not (Sys.file_exists benchmark) then fail "benchmark does not exist: %s" benchmark;
  if sha256 baseline_path <> frozen_baseline_sha256 then
    fail "Phase0 baseline digest drift";
  List.iter
    (fun scenario ->
      ignore (baseline_runs ~baseline_path ~profile ~width ~height scenario))
    scenarios;
  let commit = if smoke || dry_run then git [ "rev-parse"; "HEAD" ] else clean_commit () in
  let executable_digest = sha256 benchmark in
  let protocol_executable_digest = sha256 Sys.executable_name in
  let samples_json = ref [] in
  for sample_index = 1 to runs do
    List.iter
      (fun scenario ->
        List.iter
          (fun visibility ->
            let argv =
              [| benchmark; scenario
               ; "--visibility"; visibility
               ; "--width"; string_of_int width
               ; "--height"; string_of_int height
               ; "--warmup-seconds"; Printf.sprintf "%.9g" warmup_seconds
               ; "--sample-seconds"; Printf.sprintf "%.9g" sample_seconds
              |]
            in
            Printf.printf "[%d/%d] %s/%s\n%!" sample_index runs scenario visibility;
            if dry_run then Printf.printf "  %s\n%!" (String.concat " " (Array.to_list argv))
            else
              let raw = capture argv in
              samples_json :=
                `Assoc
                  [ "sample_index", `Int sample_index
                  ; "scenario", `String scenario
                  ; "visibility", `String visibility
                  ; "raw", raw
                  ]
                :: !samples_json)
          visibilities)
      scenarios
  done;
  if dry_run then () else begin
    if not smoke then begin
      if clean_commit () <> commit then fail "source commit changed during R10";
      if sha256 benchmark <> executable_digest then
        fail "benchmark executable changed during R10"
    end;
    let protocol =
      `Assoc
        [ "profile", `String profile; "width", `Int width; "height", `Int height
        ; "samples", `Int runs; "warmup_seconds", `Float warmup_seconds
        ; "sample_seconds", `Float sample_seconds; "smoke", `Bool smoke
        ; "ordering", `String "round-major/scenario-major/visibility-minor"
        ]
    in
    let provisional =
      `Assoc
        [ "schema", `String "prismel-r10-native/v1"
        ; "protocol", protocol
        ; "provenance",
            `Assoc
              [ "git_commit", `String commit; "git_dirty", `Bool smoke
              ; "benchmark", `String benchmark
              ; "executable_sha256", `String executable_digest
              ; "protocol_executable", `String Sys.executable_name
              ; "protocol_executable_sha256", `String protocol_executable_digest
              ; "baseline_path", `String baseline_path
              ; "baseline_sha256", `String frozen_baseline_sha256
              ]
        ; "samples", `List (List.rev !samples_json)
        ]
    in
    let summaries = validate_report provisional in
    let report = match provisional with
      | `Assoc fields -> `Assoc (fields @ [ "summaries", `List summaries ])
      | _ -> assert false
    in
    ignore (validate_report report);
    write_json output report;
    Printf.printf "R10 native qualification passed: %s\n%!" output
  end

let synthetic_raw ~scenario ~visibility run =
  let frames = integer scenario (field scenario "frames" run) in
  `Assoc
    [ "profile", `String "release"; "width", `Int 640; "height", `Int 480
    ; "scenario", `String (expected_raw_scenario scenario)
    ; "visibility", `String visibility
    ; "observed_visible", `Bool (visibility = "visible")
    ; "semantics_supported", `Bool true; "sample_frames", `Int frames
    ; "wall_seconds", field scenario "wall_seconds" run
    ; "user_seconds", field scenario "user_seconds" run
    ; "system_seconds", field scenario "system_seconds" run
    ; "median_ms", `Float (1000. *. number scenario (field scenario "median_frame_seconds" run))
    ; "p95_ms", `Float (1000. *. number scenario (field scenario "p95_frame_seconds" run))
    ; "promoted_bytes", field scenario "promoted_bytes" run
    ; "peak_sampled_rss_kib", field scenario "peak_sampled_rss_kib" run
    ; "workload_signature", `String ("r10-test/" ^ scenario)
    ; "canonical_framebuffer_digest", `String ("digest-" ^ scenario)
    ; "canonical_pixel_authority", `String ("r10-canonical-frame-1/" ^ scenario)
    ; "work_units", `Int 100
    ]

let self_test baseline_path =
  if sha256 baseline_path <> frozen_baseline_sha256 then fail "self-test baseline drift";
  let sample_values = ref [] in
  List.iter
    (fun scenario ->
      let runs = baseline_runs ~baseline_path ~profile:"release" ~width:640 ~height:480 scenario in
      List.iter
        (fun visibility ->
          List.iteri
            (fun index run ->
              sample_values :=
                `Assoc
                  [ "sample_index", `Int (index + 1); "scenario", `String scenario
                  ; "visibility", `String visibility
                  ; "raw", synthetic_raw ~scenario ~visibility run
                  ]
                :: !sample_values)
            runs)
        visibilities)
    scenarios;
  let report =
    `Assoc
      [ "schema", `String "prismel-r10-native/v1"
      ; "protocol", `Assoc
          [ "profile", `String "release"; "width", `Int 640; "height", `Int 480
          ; "samples", `Int 5; "warmup_seconds", `Float 3.
          ; "sample_seconds", `Float 30.; "smoke", `Bool false ]
      ; "provenance", `Assoc
          [ "git_commit", `String (String.make 40 'a'); "git_dirty", `Bool false
          ; "executable_sha256", `String (String.make 64 'b')
          ; "protocol_executable_sha256", `String (String.make 64 'c')
          ; "baseline_path", `String baseline_path
          ; "baseline_sha256", `String frozen_baseline_sha256 ]
      ; "samples", `List (List.rev !sample_values)
      ]
  in
  ignore (validate_report report);
  let broken =
    match report with
    | `Assoc fields ->
        `Assoc (List.map (fun (name, value) ->
          if name = "samples" then
            match value with `List (_ :: rest) -> name, `List rest | _ -> name, value
          else name, value) fields)
    | _ -> assert false
  in
  (try
     ignore (validate_report broken);
     fail "self-test accepted a missing cell sample"
   with Invalid_report _ -> ());
  let dirty =
    match report with
    | `Assoc fields ->
        `Assoc (List.map (fun (name, value) ->
          if name = "provenance" then
            match value with
            | `Assoc provenance ->
                name, `Assoc (List.map (fun (key, child) ->
                  if key = "git_dirty" then key, `Bool true else key, child)
                  provenance)
            | _ -> name, value
          else name, value) fields)
    | _ -> assert false
  in
  (try
     ignore (validate_report dirty);
     fail "self-test accepted dirty qualification provenance"
   with Invalid_report _ -> ());
  print_endline "R10 native protocol self-test passed"

let protect action =
  try action () with
  | Invalid_report message ->
      prerr_endline ("R10 native: " ^ message);
      exit 2
