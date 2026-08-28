open Yojson.Safe.Util

let fail format = Printf.ksprintf (fun message -> prerr_endline ("R10: " ^ message); exit 2) format
let member_opt name json = match member name json with `Null -> None | value -> Some value
let first names json = List.find_map (fun name -> member_opt name json) names
let string_or_null = function Some (`String value) -> `String value | _ -> `Null
let number_or_null = function
  | Some ((`Int _ | `Intlit _ | `Float _) as value) -> value | _ -> `Null
let int_or_null = function Some (`Int _ as value) -> value | _ -> `Null

let read_json path = Yojson.Safe.from_file path
let write_json path json =
  let channel = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out channel)
    (fun () -> Yojson.Safe.pretty_to_channel channel json; output_char channel '\n')

let capture argv =
  if Array.length argv = 0 then fail "empty child argv";
  let output = Filename.temp_file "prismel-r10-" ".json" in
  let errors = Filename.temp_file "prismel-r10-" ".stderr" in
  let fd = Unix.openfile output [Unix.O_WRONLY; Unix.O_TRUNC] 0o600 in
  let error_fd = Unix.openfile errors [Unix.O_WRONLY; Unix.O_TRUNC] 0o600 in
  let pid = Unix.create_process argv.(0) argv Unix.stdin fd error_fd in
  Unix.close fd; Unix.close error_fd;
  let read_text path =
    let input = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in input) (fun () ->
      really_input_string input (in_channel_length input) |> String.trim) in
  let cleanup () = Sys.remove output; Sys.remove errors in
  match snd (Unix.waitpid [] pid) with
  | Unix.WEXITED 0 ->
      Ok (Fun.protect ~finally:cleanup (fun () -> read_json output))
  | Unix.WEXITED code ->
      let detail = read_text errors in cleanup ();
      Error (Printf.sprintf "child %s exited %d: %s" argv.(0) code detail)
  | Unix.WSIGNALED signal | Unix.WSTOPPED signal ->
      let detail = read_text errors in cleanup ();
      Error (Printf.sprintf "child %s received signal %d: %s" argv.(0) signal detail)

let command_output program arguments =
  let argv = Array.of_list (program :: arguments) in
  let input = Unix.open_process_args_in program argv in
  let buffer = Buffer.create 128 in
  (try while true do Buffer.add_string buffer (input_line input); Buffer.add_char buffer '\n' done
   with End_of_file -> ());
  match Unix.close_process_in input with
  | Unix.WEXITED 0 -> String.trim (Buffer.contents buffer)
  | _ -> fail "%s failed while recording provenance" program

let optional_command_output program arguments =
  let argv = Array.of_list (program :: arguments) in
  try
    let input = Unix.open_process_args_in program argv in
    let line = try Some (String.trim (input_line input)) with End_of_file -> None in
    match Unix.close_process_in input with Unix.WEXITED 0 -> line | _ -> None
  with Unix.Unix_error _ -> None

let run_command program arguments =
  let argv=Array.of_list(program::arguments)in
  match snd(Unix.waitpid[](Unix.create_process program argv Unix.stdin Unix.stdout Unix.stderr))with
  |Unix.WEXITED 0->()
  |Unix.WEXITED code->fail "%s exited %d during executable freshness preflight"program code
  |Unix.WSIGNALED signal|Unix.WSTOPPED signal->
      fail "%s received signal %d during executable freshness preflight"program signal

let executable_paths cases =
  let paths=List.concat_map(fun case->
    let command=case|>member"command"|>to_list|>List.map to_string in
    match command with
    |[]->fail"manifest contains an empty command"
    |program::_->
        let rec nested acc=function
          |"--executable"::path::rest->nested(path::acc)rest
          |_::rest->nested acc rest|[]->List.rev acc in
        program::nested[]command)cases in
  List.sort_uniq String.compare paths

let build_target path =
  let prefix="_build/default/"in
  if String.starts_with~prefix path then
    String.sub path(String.length prefix)(String.length path-String.length prefix)
  else fail"manifest executable %s is outside _build/default; cannot prove Dune freshness"path

let executable_identity path =
  if not(Sys.file_exists path)then fail"Dune did not produce manifest executable %s"path;
  let stat=Unix.stat path in
  let digest=command_output "/usr/bin/shasum"["-a";"256";path]
    |> String.split_on_char ' '|>List.hd in
  if String.length digest<>64 then fail"could not hash manifest executable %s"path;
  `Assoc["path",`String path;"sha256",`String digest;
    "size_bytes",`Int stat.st_size;"mtime",`Float stat.st_mtime]

let preflight_executables ~profile cases =
  let paths=executable_paths cases in
  let targets=List.map build_target paths in
  run_command"dune"("build"::"--profile"::profile::targets);
  List.map executable_identity paths

let replace token value text =
  let rec loop offset result =
    match String.index_from_opt text offset '{' with
    | None -> Buffer.add_substring result text offset (String.length text - offset)
    | Some index ->
        Buffer.add_substring result text offset (index - offset);
        if String.length text - index >= String.length token
           && String.sub text index (String.length token) = token then begin
          Buffer.add_string result value; loop (index + String.length token) result
        end else begin Buffer.add_char result text.[index]; loop (index + 1) result end
  in
  let result = Buffer.create (String.length text) in loop 0 result; Buffer.contents result

let interpolate ~seconds ~warmup ~profile ~width ~height value =
  value |> replace "{seconds}" (Printf.sprintf "%.6g" seconds)
  |> replace "{warmup}" (Printf.sprintf "%.6g" warmup)
  |> replace "{profile}" profile |> replace "{width}" (string_of_int width)
  |> replace "{height}" (string_of_int height)

let uname flag = command_output "/usr/bin/uname" [flag]
let sysctl name = optional_command_output "/usr/sbin/sysctl" ["-n"; name]

let machine_facts () = `Assoc [
  "os", `String (uname "-s"); "os_release", `String (uname "-r");
  "architecture", `String (uname "-m"); "hostname", `String (uname "-n");
  "cpu_model", string_or_null (Option.map (fun x -> `String x) (sysctl "machdep.cpu.brand_string"));
  "logical_cpu_count", number_or_null (Option.map (fun x -> `Int (int_of_string x)) (sysctl "hw.logicalcpu"));
  "memory_bytes", string_or_null (Option.map (fun x -> `String x) (sysctl "hw.memsize"));
  "ocaml_version", `String Sys.ocaml_version ]

let metric raw names = number_or_null (first names raw)
let numeric_float = function
  | Some (`Float value) -> Some value
  | Some (`Int value) -> Some (float value)
  | Some (`Intlit value) -> (try Some (float_of_string value) with Failure _ -> None)
  | _ -> None
let numeric_int value = Option.map int_of_float (numeric_float value)
let canonical_git_commit value =
  String.length value = 40 && String.for_all (function
    | '0'..'9' | 'a'..'f' -> true | _ -> false) value
let seconds_metric raw seconds_names millisecond_names =
  match first seconds_names raw with
  | Some value -> number_or_null (Some value)
  | None -> (match first millisecond_names raw with
      | Some (`Float value) -> `Float (value /. 1000.)
      | Some (`Int value) -> `Float (float value /. 1000.)
      | _ -> `Null)
let divided_metric raw names denominator =
  match numeric_float (first names raw), denominator with
  | Some value, Some count when count > 0 -> `Float (value /. float count)
  | _ -> `Null
let normalize ~protocol ~case ~sample_index raw =
  let get_string key = case |> member key |> to_string in
  let case_profile = get_string "profile" in
  (match first ["profile"] raw with
   | Some (`String child_profile) when child_profile <> case_profile ->
       fail "%s/%s child profile %s does not match manifest profile %s"
         (get_string "target") (get_string "scenario") child_profile case_profile
   | _ -> ());
  let raw_window = match member "window" raw with `Assoc _ as value -> value | _ -> `Null in
  let direct_or_window name = match first [name] raw with
    | Some value -> Some value
    | None -> (match raw_window with `Assoc _ -> member_opt name raw_window | _ -> None) in
  let measured_logical dimension drawable =
    match numeric_int (first [dimension] raw) with
    | Some value -> value
    | None -> (match numeric_int (direct_or_window drawable),
                    numeric_float (direct_or_window "pixel_density") with
        | Some pixels, Some density when density > 0. ->
            int_of_float (Float.round (float pixels /. density))
        | _ -> fail "%s/%s child did not report a measurable logical %s"
            (get_string "target") (get_string "scenario") dimension)
  in
  let measured_width = measured_logical "width" "drawable_width"
  and measured_height = measured_logical "height" "drawable_height" in
  let user = first ["user_seconds"] raw and system = first ["system_seconds"] raw in
  let frame_count = numeric_int (first ["frames"; "sample_frames"] raw) in
  let cpu_seconds = match user, system with
    | Some (`Float u), Some (`Float s) -> `Float (u +. s)
    | Some (`Int u), Some (`Int s) -> `Int (u + s)
    | _ -> number_or_null (first ["cpu_seconds"; "cpu"] raw) in
  `Assoc [
    "schema", `String "prismel-r10-performance/v1";
    "protocol", protocol; "sample_index", `Int sample_index;
    "engine", `String (get_string "engine"); "target", `String (get_string "target");
    "scenario", `String (get_string "scenario"); "profile", `String case_profile;
    "resolution", `Assoc ["logical_width", `Int measured_width; "logical_height", `Int measured_height;
      "drawable_width", int_or_null (direct_or_window "drawable_width");
      "drawable_height", int_or_null (direct_or_window "drawable_height");
      "pixel_scale", (match first ["pixel_scale"] raw with
        | Some value -> value
        | None -> (match direct_or_window "pixel_density" with Some value -> value | None -> `Null))];
    "timing", `Assoc ["wall_seconds", metric raw ["wall_seconds"; "wall"];
      "user_seconds", metric raw ["user_seconds"]; "system_seconds", metric raw ["system_seconds"];
      "cpu_seconds", cpu_seconds; "cpu_percent", metric raw ["cpu_percent"];
      "median_frame_seconds", seconds_metric raw ["median_frame_seconds"] ["median_ms"];
      "p95_frame_seconds", seconds_metric raw ["p95_frame_seconds"] ["p95_ms"];
      "p99_frame_seconds", seconds_metric raw ["p99_frame_seconds"] ["p99_ms"]];
    "pacing", `Assoc ["scheduling", string_or_null (first ["scheduling"] raw);
      "scheduled_frame_rate", number_or_null (first ["scheduled_frame_rate"] raw)];
    "memory", `Assoc ["allocated_bytes", metric raw ["allocated_bytes"; "allocated"];
      "promoted_bytes", metric raw ["promoted_bytes"; "promoted"];
      "allocated_bytes_per_frame", (match first ["allocated_bytes_per_frame"] raw with
        | Some value -> number_or_null (Some value)
        | None -> divided_metric raw ["allocated_bytes"; "allocated"] frame_count);
      "promoted_bytes_per_frame", (match first ["promoted_bytes_per_frame"] raw with
        | Some value -> number_or_null (Some value)
        | None -> divided_metric raw ["promoted_bytes"; "promoted"] frame_count);
      "peak_rss_kib", metric raw ["peak_sampled_rss_kib"; "rss_kib"; "rss"]];
    "work", `Assoc ["upload_bytes", (match first ["measurement_upload_bytes"; "upload_bytes_during_measurement"; "legacy_upload_bytes"] raw with Some value -> value | None -> `Null);
      "frame_count", (match frame_count with Some value -> `Int value | None -> `Null);
      "work_units", int_or_null (first ["work_units"; "triangles"; "legacy_work_units"] raw);
      "draw_count", int_or_null (first ["draw_count"; "draws"; "legacy_draw_count"] raw);
      "pass_count", int_or_null (first ["pass_count"; "passes"] raw);
      "backend_calls", int_or_null (first ["backend_calls"; "ffi_boundary_calls"] raw)];
    "equivalence", `Assoc [
      "workload_signature", string_or_null (first ["workload_signature"] raw);
      "semantics_supported", (match first ["semantics_supported"] raw with
        | Some (`Bool _ as value) -> value | _ -> `Null);
      "pixel_hash", string_or_null (first ["pixel_hash"; "framebuffer_hash"; "framebuffer_digest"] raw);
      "pixel_authority", string_or_null (first ["pixel_authority"] raw);
      "pixel_tolerance", number_or_null (first ["pixel_tolerance"] raw)];
    "gpu", `Assoc ["duration_seconds", number_or_null (first ["gpu_duration_seconds"; "legacy_gpu_duration_seconds"] raw);
      "utilization_percent", number_or_null (first ["gpu_utilization_percent"; "legacy_gpu_utilization_percent"] raw);
      "counters", (match first ["native_gpu_counters"] raw with Some value -> value | None -> `Null)];
    "thermal", `Assoc ["state", string_or_null (direct_or_window "thermal_state");
      "power_state", string_or_null (direct_or_window "power_state")];
    "raw", raw ]

let required_scenarios = ["basic"; "pxui"; "canvas"; "scene3"]
let required_targets = ["runtime-next-native"; "runtime-next-native-hidden"; "headless"; "web"; "legacy"]

let require_equivalent_work samples scenario =
  let matching = List.filter (fun sample -> member "scenario" sample = `String scenario) samples in
  let exact_string field sample =
    let value = match member "equivalence" sample with
      | `Assoc _ as equivalence -> member field equivalence
      | _ -> `Null in
    match value with
    | `String value when value <> "" -> value
    | _ -> fail "%s/%s lacks required equivalence %s"
        (sample |> member "target" |> to_string) scenario field
  in
  let exact_positive field sample =
    match sample |> member "work" |> member field with
    | `Int value when value > 0 -> value
    | _ -> fail "%s/%s lacks positive %s"
        (sample |> member "target" |> to_string) scenario field
  in
  let unique values = List.sort_uniq String.compare values in
  let signatures = unique (List.map (exact_string "workload_signature") matching)
  and work_units = List.map (exact_positive "work_units") matching |> List.sort_uniq Int.compare in
  if List.length signatures <> 1 then fail "%s workload signatures differ" scenario;
  if List.length work_units <> 1 then fail "%s work cardinality differs" scenario;
  List.iter (fun sample ->
    let target=sample|>member "target"|>to_string in
    let equivalence=member "equivalence" sample in
    if member "semantics_supported" equivalence <> `Bool true then
      fail "%s/%s does not support the exact neutral descriptor" target scenario;
    ignore(exact_string "pixel_hash" sample);
    let authority=exact_string "pixel_authority" sample in
    let expected=Printf.sprintf "phase0/%s/%s" target scenario in
    if authority<>expected then fail "%s/%s pixel authority %s is not %s"
      target scenario authority expected;
    match numeric_float(member_opt "pixel_tolerance" equivalence)with
    |Some value when Float.is_finite value&&value>=0.->()
    |_->fail "%s/%s lacks non-negative pixel tolerance provenance" target scenario)
    matching;
  List.iter(fun target->
    let target_samples=List.filter(fun sample->member "target" sample=`String target)matching in
    let hashes=unique(List.map(exact_string "pixel_hash")target_samples)
    and authorities=unique(List.map(exact_string "pixel_authority")target_samples)in
    if List.length hashes<>1 then fail "%s/%s pixel authority hash drift"target scenario;
    if List.length authorities<>1 then fail "%s/%s pixel provenance drift"target scenario)
    required_targets;
  List.iter (fun sample -> ignore (exact_positive "frame_count" sample)) matching;
  List.iter (fun sample ->
    let target = sample |> member "target" |> to_string in
    let memory = member "memory" sample in
    List.iter (fun field -> if member field memory = `Null then
      fail "%s/%s missing normalized %s" target scenario field)
      ["allocated_bytes_per_frame"; "promoted_bytes_per_frame"])
    matching

let required_number ~target ~scenario section field sample =
  let container = member section sample in
  match numeric_float (member_opt field container) with
  | Some value when Float.is_finite value && value >= 0. -> value
  | _ -> fail "%s/%s missing finite non-negative %s.%s"
      target scenario section field

let percentile fraction values =
  match List.sort Float.compare values with
  | [] -> invalid_arg "R10 percentile of empty samples"
  | sorted ->
      let count = List.length sorted in
      let index = max 0 (min (count - 1) (int_of_float (ceil (fraction *. float count)) - 1)) in
      List.nth sorted index

let import_performance_baselines ~path ~profile ~width ~height =
  let document = read_json path in
  let groups = document |> member "groups" |> to_list in
  let metric runs field derive =
    let values = List.map (fun run -> derive run field) runs in
    `Assoc ["median", `Float (percentile 0.5 values);
      "p95", `Float (percentile 0.95 values)]
  in
  let number run field = match numeric_float (member_opt field run) with
    | Some value when Float.is_finite value && value >= 0. -> value
    | _ -> fail "Phase0 baseline %s lacks finite non-negative %s"
        (run |> member "scenario" |> to_string) field in
  let per_frame run field =
    let frames = number run "frames" in
    if frames <= 0. then fail "Phase0 baseline has non-positive frame count";
    number run field /. frames
  in
  let target_name = function
    | "headless" -> Some "headless" | "web" -> Some "web" | _ -> None in
  List.filter_map (fun group ->
    match String.split_on_char ':' (group |> member "key" |> to_string) with
    | ["renderer"; baseline_target; scenario] ->
        Option.map (fun target ->
          let runs = group |> member "runs" |> to_list in
          if List.length runs <> 5 then
            fail "Phase0 baseline %s/%s has %d runs, expected 5"
              target scenario (List.length runs);
          List.iter (fun run ->
            if member "profile" run <> `String profile then
              fail "Phase0 baseline %s/%s profile does not match %s" target scenario profile;
            if member "width" run <> `Int width || member "height" run <> `Int height then
              fail "Phase0 baseline %s/%s is not %dx%d" target scenario width height)
            runs;
          let ordinary field = metric runs field number in
          let frame = `Assoc ["median", `Float (percentile 0.5
              (List.map (fun run -> number run "median_frame_seconds") runs));
            "p95", `Float (percentile 0.5
              (List.map (fun run -> number run "p95_frame_seconds") runs))] in
          `Assoc ["target", `String target; "scenario", `String scenario;
            "authority", `String (Printf.sprintf "%s#%s" path
              (group |> member "key" |> to_string));
            "profile", `String profile; "width", `Int width; "height", `Int height;
            "metrics", `Assoc ["wall", ordinary "wall_seconds"; "frame", frame;
              "CPU", metric runs "cpu_seconds" (fun run _ ->
                number run "user_seconds" +. number run "system_seconds");
              "promoted", metric runs "promoted_bytes" per_frame;
              "RSS", ordinary "peak_sampled_rss_kib"]])
          (target_name baseline_target)
    | _ -> None) groups

let enforce_performance ~profile ~width ~height samples baselines scenario =
  let for_target target =
    List.filter (fun sample ->
      member "target" sample = `String target
      && member "scenario" sample = `String scenario) samples
  in
  let metric section field target =
    List.map (required_number ~target ~scenario section field) (for_target target)
  in
  let checks =
    [ "wall", "timing", "wall_seconds", None
    ; "frame", "timing", "median_frame_seconds", Some "p95_frame_seconds"
    ; "CPU", "timing", "cpu_seconds", None
    ; "promoted", "memory", "promoted_bytes_per_frame", None
    ; "RSS", "memory", "peak_rss_kib", None
    ]
  in
  let summary target label section median_field p95_field =
    let values = metric section median_field target in
    let median = percentile 0.5 values in
    let p95 = match p95_field with
      | None -> percentile 0.95 values
      (* Frame p95 is already a within-run percentile.  Aggregate the five
         independent runs by their median rather than taking a p95-of-p95. *)
      | Some field -> percentile 0.5 (metric section field target) in
    label, median, p95
  in
  let artifact target label =
    let matches = List.filter (fun value ->
      member "target" value = `String target
      && member "scenario" value = `String scenario) baselines in
    match matches with
    | [value] ->
        if member "profile" value <> `String profile then
          fail "%s/%s performance baseline profile mismatch" target scenario;
        if member "width" value <> `Int width || member "height" value <> `Int height then
          fail "%s/%s performance baseline resolution mismatch" target scenario;
        (match member "authority" value with `String text when text <> "" -> ()
         | _ -> fail "%s/%s performance baseline lacks authority" target scenario);
        let metric = member "metrics" value |> member label in
        let number field = match numeric_float (member_opt field metric) with
          | Some value when Float.is_finite value && value >= 0. -> value
          | _ -> fail "%s/%s performance baseline lacks %s.%s"
              target scenario label field in
        number "median", number "p95"
    | [] -> fail "%s/%s has no matching authoritative Phase0 performance baseline"
        target scenario
    | _ -> fail "%s/%s has duplicate Phase0 performance baselines" target scenario
  in
  List.iter (fun target ->
    if target <> "legacy" then
      List.iter (fun (label, section, median_field, p95_field) ->
        let _, candidate_median, candidate_p95 =
          summary target label section median_field p95_field in
        let baseline_median, baseline_p95 =
          if target = "runtime-next-native" || target = "runtime-next-native-hidden" then
            let _, median, p95 = summary "legacy" label section median_field p95_field in
            median, p95
          else artifact target label in
        let ratio value baseline =
          if baseline = 0. then if value = 0. then 1. else infinity
          else value /. baseline
        in
        let median_ratio = ratio candidate_median baseline_median
        and p95_ratio = ratio candidate_p95 baseline_p95 in
        if median_ratio > 1.05 then
          fail "%s/%s %s median regressed %.3fx (maximum 1.05x)"
            target scenario label median_ratio;
        if p95_ratio > 1.10 then
          fail "%s/%s %s p95 regressed %.3fx (maximum 1.10x)"
            target scenario label p95_ratio)
        checks)
    required_targets

let validate_report report =
  let protocol = member "protocol" report in
  let expected = protocol |> member "samples" |> to_int
  and profile = protocol |> member "profile" |> to_string
  and width = protocol |> member "width" |> to_int
  and height = protocol |> member "height" |> to_int
  and sample_seconds = protocol |> member "sample_seconds" |> to_float in
  let smoke = member "smoke" protocol = `Bool true in
  if not smoke then begin
    let provenance=member "provenance" report in
    (match member "git_dirty" provenance with
     |`Bool false->()
     |`Bool true->fail "R10 qualification report was captured from a dirty worktree"
     |_->fail "R10 qualification report lacks git_dirty provenance");
    (match member "git_commit" provenance with
     |`String commit when canonical_git_commit commit->()
     |_->fail "R10 qualification report lacks a canonical git commit");
    let identities=match member"executables"provenance with
      |`List(_::_ as values)->values|_->fail"R10 qualification report lacks executable identities"in
    List.iter(fun identity->
      let path=identity|>member"path"|>to_string
      and digest=identity|>member"sha256"|>to_string in
      if path=""||String.length digest<>64||not(String.for_all(function
        |'0'..'9'|'a'..'f'->true|_->false)digest)then
        fail"R10 qualification report has an invalid executable identity")identities
  end;
  let samples = report |> member "samples" |> to_list in
  let baselines = match member "performance_baselines" report with
    | `List values -> values | `Null -> []
    | _ -> fail "performance_baselines must be a list" in
  let count target scenario = List.filter (fun sample ->
    member "target" sample = `String target && member "scenario" sample = `String scenario) samples in
  List.iter (fun target -> List.iter (fun scenario ->
    let found = count target scenario in
    if List.length found <> expected then fail "%s/%s has %d samples, expected %d" target scenario (List.length found) expected;
    List.iter (fun sample ->
      if member "profile" sample <> `String profile then fail "%s/%s profile mismatch" target scenario;
      let resolution = member "resolution" sample in
      if member "logical_width" resolution <> `Int width || member "logical_height" resolution <> `Int height then
        fail "%s/%s resolution mismatch" target scenario;
      let timing = member "timing" sample in
      List.iter (fun key -> if member key timing = `Null then fail "%s/%s missing %s" target scenario key)
        ["wall_seconds"; "median_frame_seconds"; "p95_frame_seconds"; "p99_frame_seconds"]
      ;
      let pacing=member "pacing" sample in
      let scheduling=match pacing with `Assoc _->member "scheduling"pacing|_->`Null in
      if not smoke && scheduling<>`String"duration-bounded"then
        fail "%s/%s does not report duration-bounded scheduling"target scenario;
      let frames=sample|>member "work"|>member "frame_count"|>to_int
      and wall=timing|>member "wall_seconds"|>to_float in
      if frames <= 0 then fail "%s/%s emitted no measured frames" target scenario;
      if smoke then begin
        List.iter (fun field -> ignore (required_number ~target ~scenario "timing" field sample))
          ["wall_seconds"; "cpu_seconds"; "median_frame_seconds";
           "p95_frame_seconds"; "p99_frame_seconds"];
        List.iter (fun field -> ignore (required_number ~target ~scenario "memory" field sample))
          ["allocated_bytes_per_frame"; "promoted_bytes_per_frame"; "peak_rss_kib"]
      end;
      if not smoke &&
         (wall < sample_seconds *. 0.90 || wall > sample_seconds *. 1.10) then
        fail "%s/%s wall interval %.3fs differs from requested %.3fs by more than 10%%"target scenario wall sample_seconds
    ) found
  ) required_scenarios) required_targets;
  List.iter (require_equivalent_work samples) required_scenarios;
  if not smoke then
    List.iter (enforce_performance ~profile ~width ~height samples baselines) required_scenarios;
  print_endline "R10 validation passed"

let () =
  let manifest_path = ref None and output_path = ref None and validate_path = ref None
  and smoke = ref false and dry_run = ref false in
  Arg.parse [
    "--manifest", Arg.String (fun x -> manifest_path := Some x), "JSON command manifest";
    "--output", Arg.String (fun x -> output_path := Some x), "normalized report";
    "--validate", Arg.String (fun x -> validate_path := Some x), "validate normalized report";
    "--smoke", Arg.Set smoke, "one warmed short sample per case";
    "--dry-run", Arg.Set dry_run, "print child commands without executing" ] ignore "R10 cross-target protocol";
  match !validate_path with
  | Some path -> validate_report (read_json path)
  | None ->
      let manifest = read_json (Option.get !manifest_path) in
      let configured_samples = manifest |> member "samples" |> to_int in
      let profile = manifest |> member "profile" |> to_string
      and width = manifest |> member "width" |> to_int
      and height = manifest |> member "height" |> to_int in
      let baseline_path = match member "performance_baseline" manifest with
        | `String path when path <> "" -> path
        | _ -> fail "manifest lacks performance_baseline artifact path" in
      let performance_baselines =
        import_performance_baselines ~path:baseline_path ~profile ~width ~height in
      let seconds = if !smoke then 0.05 else manifest |> member "sample_seconds" |> to_float
      and warmup = if !smoke then 0.02 else manifest |> member "warmup_seconds" |> to_float in
      let runs = if !smoke then 1 else configured_samples in
      let cases = manifest |> member "cases" |> to_list in
      let commit_before=command_output "/usr/bin/git" ["rev-parse";"HEAD"]in
      if command_output "/usr/bin/git" ["status";"--porcelain"]<>""then
        fail"R10 protocol requires a clean worktree before executable preflight";
      let executable_identities=preflight_executables~profile cases in
      let commit_after=command_output "/usr/bin/git" ["rev-parse";"HEAD"]in
      if commit_after<>commit_before||command_output "/usr/bin/git" ["status";"--porcelain"]<>""then
        fail"source provenance changed during executable freshness preflight";
      let protocol = `Assoc ["name", `String "R10"; "profile", member "profile" manifest;
        "width", member "width" manifest; "height", member "height" manifest;
        "samples", `Int runs; "sample_seconds", `Float seconds; "warmup_seconds", `Float warmup;
        "smoke", `Bool !smoke] in
      let collected = ref [] and failures = ref [] in
      (* Round-major ordering interleaves targets/scenarios and limits thermal/order bias. *)
      for sample_index = 1 to runs do List.iter (fun case ->
        let command = case |> member "command" |> to_list |> List.map to_string
          |> List.map (interpolate ~seconds ~warmup ~profile ~width ~height) in
        Printf.printf "[%d/%d] %s\n%!" sample_index runs (String.concat " " command);
        if not !dry_run then match capture (Array.of_list command) with
          | Ok raw -> collected := normalize ~protocol ~case ~sample_index raw :: !collected
          | Error message ->
              prerr_endline ("R10: " ^ message);
              failures := `Assoc ["sample_index", `Int sample_index;
                "engine", member "engine" case; "target", member "target" case;
                "scenario", member "scenario" case; "message", `String message] :: !failures
      ) cases done;
      if not !dry_run then begin
        if command_output "/usr/bin/git" ["rev-parse";"HEAD"]<>commit_before||
           command_output "/usr/bin/git" ["status";"--porcelain"]<>""then
          fail"source provenance changed during R10 measurement";
        let identities_after=List.map executable_identity(executable_paths cases)in
        if identities_after<>executable_identities then
          fail"a manifest executable changed during R10 measurement";
        let report = `Assoc ["schema", `String "prismel-r10-suite/v1";
          "protocol", protocol;
          "provenance", `Assoc ["git_commit", `String commit_before;
            "git_dirty", `Bool (command_output "/usr/bin/git" ["status"; "--porcelain"] <> "");
            "executable_build",`String"dune-build-current-clean-commit";
            "executables",`List executable_identities;
            "machine", machine_facts (); "display", member "display" manifest];
          "samples", `List (List.rev !collected);
          "performance_baselines", `List performance_baselines;
          "failures", `List (List.rev !failures)] in
        let output = Option.get !output_path in write_json output report;
        if !failures <> [] then begin
          Printf.eprintf "R10: %d child cell(s) failed; partial report: %s\n%!"
            (List.length !failures) output; exit 2
        end else validate_report report
      end
