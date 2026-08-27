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
      "pixel_hash", string_or_null (first ["pixel_hash"; "framebuffer_hash"; "framebuffer_digest"] raw)];
    "gpu", `Assoc ["duration_seconds", number_or_null (first ["gpu_duration_seconds"; "legacy_gpu_duration_seconds"] raw);
      "utilization_percent", number_or_null (first ["gpu_utilization_percent"; "legacy_gpu_utilization_percent"] raw);
      "counters", (match first ["native_gpu_counters"] raw with Some value -> value | None -> `Null)];
    "thermal", `Assoc ["state", string_or_null (direct_or_window "thermal_state");
      "power_state", string_or_null (direct_or_window "power_state")];
    "raw", raw ]

let required_scenarios = ["basic"; "pxui"; "canvas"; "scene3"]
let required_targets = ["runtime-next-native"; "headless"; "web"; "legacy"]

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
  and pixels = unique (List.map (exact_string "pixel_hash") matching)
  and work_units = List.map (exact_positive "work_units") matching |> List.sort_uniq Int.compare in
  if List.length signatures <> 1 then fail "%s workload signatures differ" scenario;
  if List.length pixels <> 1 then fail "%s pixel hashes differ" scenario;
  if List.length work_units <> 1 then fail "%s work cardinality differs" scenario;
  let frames = List.map (exact_positive "frame_count") matching in
  let minimum = List.fold_left min max_int frames
  and maximum = List.fold_left max 0 frames in
  if float maximum /. float minimum > 1.10 then
    fail "%s pacing differs by %.3fx (maximum 1.10x)" scenario
      (float maximum /. float minimum);
  List.iter (fun sample ->
    let target = sample |> member "target" |> to_string in
    let memory = member "memory" sample in
    List.iter (fun field -> if member field memory = `Null then
      fail "%s/%s missing normalized %s" target scenario field)
      ["allocated_bytes_per_frame"; "promoted_bytes_per_frame"])
    matching

let validate_report report =
  let protocol = member "protocol" report in
  let expected = protocol |> member "samples" |> to_int
  and profile = protocol |> member "profile" |> to_string
  and width = protocol |> member "width" |> to_int
  and height = protocol |> member "height" |> to_int in
  let samples = report |> member "samples" |> to_list in
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
    ) found
  ) required_scenarios) required_targets;
  List.iter (require_equivalent_work samples) ["basic"; "pxui"; "canvas"];
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
      let seconds = if !smoke then 0.05 else manifest |> member "sample_seconds" |> to_float
      and warmup = if !smoke then 0.02 else manifest |> member "warmup_seconds" |> to_float in
      let runs = if !smoke then 1 else configured_samples in
      let cases = manifest |> member "cases" |> to_list in
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
        let report = `Assoc ["schema", `String "prismel-r10-suite/v1";
          "protocol", protocol;
          "provenance", `Assoc ["git_commit", `String (command_output "/usr/bin/git" ["rev-parse"; "HEAD"]);
            "git_dirty", `Bool (command_output "/usr/bin/git" ["status"; "--porcelain"] <> "");
            "machine", machine_facts (); "display", member "display" manifest];
          "samples", `List (List.rev !collected);
          "failures", `List (List.rev !failures)] in
        let output = Option.get !output_path in write_json output report;
        if !failures <> [] then begin
          Printf.eprintf "R10: %d child cell(s) failed; partial report: %s\n%!"
            (List.length !failures) output; exit 2
        end else validate_report report
      end
