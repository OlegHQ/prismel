open Yojson.Safe.Util

exception Invalid_report of string

let fail format =
  Printf.ksprintf (fun message -> raise (Invalid_report message)) format

let scenarios = [ "basic"; "pxui"; "canvas"; "scene3" ]
let visibilities = [ "visible"; "hidden" ]
let production_benchmark =
  "_build/default/tools/runtime_next_native_benchmark/runtime_next_native_benchmark.exe"
let production_protocol_suffix =
  "_build/default/tools/r10_performance/r10_native_protocol.exe"
let qualification_schema = "prismel-r10-native-qualification/v2"
let smoke_schema = "prismel-r10-native-smoke/v1"
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

let hex64 value =
  String.length value = 64
  && String.for_all
       (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
       value

let hex32 value =
  String.length value = 32
  && String.for_all
       (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
       value

let int64_text context = function
  | `String value | `Intlit value ->
      (try
         let parsed = Int64.of_string value in
         if parsed < 0L then fail "%s is negative" context;
         parsed
       with Failure _ -> fail "%s is not a non-negative int64" context)
  | _ -> fail "%s is not an int64 string" context

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

let machine_facts () =
  let required program arguments label =
    let value = command_output program arguments in
    if value = "" then fail "machine provenance lacks %s" label;
    value
  in
  let display_json =
    required "/usr/sbin/system_profiler"
      [ "SPDisplaysDataType"; "-json" ] "display inventory"
    |> fun text ->
    try Yojson.Safe.from_string text with Yojson.Json_error message ->
      fail "display inventory is not JSON: %s" message
  in
  `Assoc
    [ "os_name", `String (required "/usr/bin/sw_vers" [ "-productName" ] "OS name")
    ; "os_version", `String (required "/usr/bin/sw_vers" [ "-productVersion" ] "OS version")
    ; "os_build", `String (required "/usr/bin/sw_vers" [ "-buildVersion" ] "OS build")
    ; "kernel", `String (required "/usr/bin/uname" [ "-r" ] "kernel")
    ; "architecture", `String (required "/usr/bin/uname" [ "-m" ] "architecture")
    ; "sdk_version", `String (required "/usr/bin/xcrun"
        [ "--sdk"; "macosx"; "--show-sdk-version" ] "macOS SDK version")
    ; "sdk_path", `String (required "/usr/bin/xcrun"
        [ "--sdk"; "macosx"; "--show-sdk-path" ] "macOS SDK path")
    ; "ocaml_version", `String Sys.ocaml_version
    ; "display_inventory", display_json
    ]

let conditions () =
  `Assoc
    [ "captured_epoch_seconds", `Float (Unix.gettimeofday ())
    ; "power", `String (command_output "/usr/bin/pmset" [ "-g"; "batt" ])
    ; "thermal", `String (command_output "/usr/bin/pmset" [ "-g"; "therm" ])
    ]

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

let contains haystack needle =
  let haystack_length=String.length haystack
  and needle_length=String.length needle in
  let rec loop offset=offset+needle_length<=haystack_length&&
    (String.sub haystack offset needle_length=needle||loop(offset+1))in
  needle_length=0||loop 0

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

let authority_scenario = function
  | "basic" -> R10_scene2_legacy_equivalent.Basic
  | "pxui" -> Pxui
  | "canvas" -> Canvas
  | "scene3" -> Scene3
  | scenario -> fail "unknown scenario %s" scenario

let expected_workload scenario =
  R10_phase0_workload_authority.expected (authority_scenario scenario)

let expected_command ~benchmark ~width ~height ~warmup_seconds ~sample_seconds
    scenario visibility =
  [ benchmark; scenario; "--visibility"; visibility
  ; "--width"; string_of_int width; "--height"; string_of_int height
  ; "--warmup-seconds"; Printf.sprintf "%.9g" warmup_seconds
  ; "--sample-seconds"; Printf.sprintf "%.9g" sample_seconds
  ]

let sample_raw context sample = field context "raw" sample

let samples_for report scenario visibility =
  report |> member "samples" |> to_list
  |> List.filter (fun sample ->
       member "scenario" sample = `String scenario
       && member "visibility" sample = `String visibility)

let check_cell_semantics ~qualification ~sample_seconds ~warmup_seconds
    ~profile ~width ~height
    scenario visibility samples =
  let signatures = ref [] and hashes = ref [] and work_units = ref [] in
  let expected_units,expected_signature=expected_workload scenario in
  List.iteri
    (fun index sample ->
      let context =
        Printf.sprintf "%s/%s run %d" scenario visibility (index + 1)
      in
      let raw = sample_raw context sample in
      if member "backend" raw <> `String "real-m1-runtime-next-metal" then
        fail "%s is not the production Metal backend" context;
      if member "benchmark_identity" raw
         <> `String "runtime-next-production-public-r10"
      then fail "%s is not the production public R10 benchmark" context;
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
      if integer context(field context "phase0_fps_configuration"raw)<>60
         ||member "measurement_clock"raw<>
           `String"phase0-prior-dt-fps60-integer-ms"
         ||integer context(field context "timing_buffer_capacity"raw)<>16_384
         ||number context(field context "rss_sample_seconds"raw)<>1. then
        fail "%s does not use the frozen Phase0 measurement harness"context;
      if boolean context (field context "observed_visible" raw)
         <> (visibility = "visible")
      then fail "%s observed visibility mismatch" context;
      if not (boolean context (field context "semantics_supported" raw)) then
        fail "%s does not support the exact workload" context;
      if number context (field context "warmup_seconds" raw) <> warmup_seconds then
        fail "%s child warmup differs from the protocol" context;
      if member "scheduling" raw <> `String "duration-bounded" then
        fail "%s child is not duration-bounded" context;
      if qualification && member "protocol_r11_requested" raw <> `Bool true then
        fail "%s child did not execute the exact 30-second protocol" context;
      let frames = integer context (field context "sample_frames" raw) in
      if frames <= 0 then fail "%s measured no frames" context;
      if frames > 10_000_000 then fail "%s has an implausible frame count" context;
      let wall = number context (field context "wall_seconds" raw) in
      if qualification
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
      if List.hd !signatures <> expected_signature
         || List.hd !work_units <> expected_units
      then fail "%s does not match the frozen Phase0 workload authority" context;
      let evidence =
        R10_phase0_workload_authority.runtime_evidence
          (authority_scenario scenario)
      in
      let exact_counter name per_frame =
        let actual = integer context (field context name raw) in
        let expected = frames * per_frame in
        if actual <> expected then
          fail "%s %s=%d, expected %d from the frozen workload lowering"
            context name actual expected
      in
      exact_counter "draws" evidence.draws_per_frame;
      exact_counter "passes" evidence.passes_per_frame;
      exact_counter "backend_calls" evidence.submissions_per_frame;
      let upload = int64_text (context ^ ".measurement_upload_bytes")
          (field context "measurement_upload_bytes" raw) in
      if evidence.uploads_full_frame_per_frame then begin
        let minimum =
          Int64.mul (Int64.of_int frames)
            (Int64.of_int (width * height * 4))
        in
        if upload < minimum then
          fail "%s uploaded %Ld bytes, below the %Ld-byte Canvas snapshot minimum"
            context upload minimum
      end;
      let offscreen_setup=member "offscreen_setup"raw
      and offscreen_measurement=member "offscreen_measurement"raw in
      let exact_offscreen context value ~frames ~draws ~passes ~submissions=
        let exact name expected=
          let actual=int64_text context(field context name value)in
          if actual<>Int64.of_int expected then
            fail "%s %s=%Ld, expected %d"context name actual expected in
        exact"frames"frames;exact"draws"draws;exact"passes"passes;
        exact"submissions"submissions;
        ignore(int64_text context(field context "uploaded_bytes"value));
        if integer context(field context "cache_entries"value)>256 then
          fail "%s offscreen cache exceeds 256 entries"context in
      (match scenario with
      |"basic"->
          exact_offscreen(context^".offscreen_setup")offscreen_setup
            ~frames:1~draws:4~passes:1~submissions:1;
          if offscreen_measurement<>`Null then
            fail "%s Basic retained an offscreen target during measurement"context
      |"canvas"->
          exact_offscreen(context^".offscreen_setup")offscreen_setup
            ~frames:1~draws:0~passes:1~submissions:1;
          exact_offscreen(context^".offscreen_measurement")offscreen_measurement
            ~frames~draws:(frames*5)~passes:frames~submissions:frames
      |"pxui"|"scene3"->if offscreen_setup<>`Null||offscreen_measurement<>`Null
          then fail "%s unexpectedly used an offscreen Canvas"context
      |_ -> assert false);
      let window=field context "window" raw in
      let logical_width=integer context(field context "logical_width" window)
      and logical_height=integer context(field context "logical_height" window)
      and drawable_width=integer context(field context "drawable_width" window)
      and drawable_height=integer context(field context "drawable_height" window)
      and density=number context(field context "pixel_density" window)
      and display_scale=number context(field context "display_scale" window)in
      if logical_width<>width||logical_height<>height||drawable_width<=0||drawable_height<=0
         ||density<=0.||display_scale<=0. then fail "%s has invalid production-window facts" context;
      if Float.abs(float drawable_width/.float logical_width-.density)>0.01 then
        fail "%s drawable width disagrees with pixel density" context;
      if Float.abs(float drawable_height/.float logical_height-.density)>0.01 then
        fail "%s drawable height disagrees with pixel density" context;
      if boolean context(field context "vsync" window) then
        fail "%s enabled presentation vsync despite frozen fps=Some 60" context;
      (match member "refresh_hz" window with `Null->()|value->
        if number context value<=0. then fail "%s has invalid refresh rate"context);
      let device=field context "metal_device" raw in
      if member "selection" device <> `String "Metal.Device.system_default" then
        fail "%s did not use the default Metal device" context;
      let device_name=string context(field context "name" device)
      and architecture=string context(field context "architecture" device)in
      if not(String.starts_with~prefix:"Apple " device_name)
         ||not(String.starts_with~prefix:"applegpu_" architecture)then
        fail "%s is not an Apple-Silicon Metal device"context;
      if int64_text context(field context "registry_id" device)<=0L then
        fail "%s has an invalid Metal registry id"context;
      ignore(boolean context(field context "low_power" device));
      ignore(boolean context(field context "removable" device));
      if not(boolean context(field context "unified_memory" device))then
        fail "%s Metal device does not report unified memory"context;
      if int64_text context(field context "recommended_max_working_set_size" device)<=0L
         ||int64_text context(field context "max_buffer_length" device)<=0L then
        fail "%s has invalid Metal capacity facts"context;
      let lifetime=field context "metal_lifetime"raw in
      let before=field context "before"lifetime
      and after=field context "after"lifetime in
      let int name value=integer context(field context name value)
      and wide name value=int64_text context(field context name value)in
      let before_created=wide"total_created"before
      and after_created=wide"total_created"after
      and before_released=wide"total_released"before
      and after_released=wide"total_released"after in
      if int"pending"after<>0||int"dropped"before<>0||int"dropped"after<>0
         ||int"live_handles"before<>int"live_handles"after
         ||Int64.sub after_created before_created<>
           Int64.sub after_released before_released
         ||wide"external_deallocation_mismatches"before<>
           wide"external_deallocation_mismatches"after then
        fail "%s leaked/dropped/mismatched native Metal handles"context;
      ignore(wide"external_deallocations"before);
      ignore(wide"external_deallocations"after);
      let gpu=field context "native_gpu_counters" raw in
      let supported=boolean context(field context "supported" gpu)in
      let status=string context(field context "status" gpu)in
      if(status="measured")<>supported||not(List.mem status["measured";"unsupported"])
      then fail "%s has inconsistent native GPU counters"context;
      let authority =
        string context (field context "canonical_pixel_source" raw)
      in
      if authority <> "candidate-stability-frame-1/" ^ scenario then
        fail "%s candidate pixel source mismatch" context;
      if string context(field context "pixel_source"raw)<>
         "runtime-next-native"^(if visibility="hidden"then"-hidden"else"")^
         "/"^scenario then fail "%s measured pixel source mismatch"context;
      if not(hex32(List.hd !hashes))then
        fail "%s canonical framebuffer digest is not lowercase MD5"context)
    samples;
  let unique compare values = List.sort_uniq compare values in
  if List.length (unique String.compare !signatures) <> 1 then
    fail "%s/%s workload signature drift" scenario visibility;
  if List.length (unique String.compare !hashes) <> 1 then
    fail "%s/%s canonical framebuffer drift" scenario visibility;
  if List.length (unique Int.compare !work_units) <> 1
     || List.hd !work_units <> expected_units
  then fail "%s/%s work cardinality drift" scenario visibility

let ratio value baseline =
  if baseline = 0. then if value = 0. then 1. else Float.infinity
  else value /. baseline

let validate_conditions context value =
  let captured=number context(field context "captured_epoch_seconds"value)
  and power=string context(field context "power"value)
  and thermal=string context(field context "thermal"value)in
  captured,power,thermal

let validate_exact_cells report ~expected ~benchmark ~width ~height
    ~warmup_seconds ~sample_seconds ~qualification =
  let samples=report|>member "samples"|>to_list in
  let expected_order=ref[]in
  for sample_index=1 to expected do
    List.iter(fun scenario->List.iter(fun visibility->
      expected_order:= (sample_index,scenario,visibility)::!expected_order)visibilities)scenarios
  done;
  let expected_order=List.rev!expected_order in
  if List.length samples<>List.length expected_order then
    fail "report has %d samples, expected exactly %d"(List.length samples)(List.length expected_order);
  let actual_order=List.map(fun sample->
    let context="sample"in
    let index=integer context(field context "sample_index"sample)
    and scenario=string context(field context "scenario"sample)
    and visibility=string context(field context "visibility"sample)in
    if not(List.mem scenario scenarios)||not(List.mem visibility visibilities)then
      fail "unknown R10 cell %s/%s"scenario visibility;
    let expected_command=expected_command~benchmark~width~height~warmup_seconds
      ~sample_seconds scenario visibility in
    let actual_command=field context "command"sample|>to_list|>List.map to_string in
    if actual_command<>expected_command then
      fail "%s/%s index %d child command drift"scenario visibility index;
    let before_time,before_power,before_thermal=
      validate_conditions(context^".conditions_before")
        (field context "conditions_before"sample)in
    let after_time,after_power,after_thermal=
      validate_conditions(context^".conditions_after")
        (field context "conditions_after"sample)in
    if after_time<before_time then fail "%s child condition timestamps are reversed"context;
    if qualification&&(not(contains before_power "AC Power")
      ||not(contains after_power "AC Power")||before_thermal<>after_thermal)then
      fail "%s qualification power/thermal conditions were not stable AC"context;
    index,scenario,visibility)samples in
  if actual_order<>expected_order then
    fail "R10 cells/indices are not exactly round-major indices 1..%d"expected;
  let devices=List.map(fun sample->member "metal_device"(sample_raw "sample" sample))samples
    |>List.sort_uniq compare in
  if List.length devices<>1 then fail "Metal device facts changed between child cells";
  let windows=List.map(fun sample->member "window"(sample_raw "sample" sample))samples
    |>List.sort_uniq compare in
  if List.length windows<>1 then fail "window/display facts changed between child cells";
  samples

let validate_machine provenance =
  let machine=field "provenance" "machine"provenance in
  List.iter(fun name->ignore(string("machine."^name)(field "machine"name machine)))
    ["os_name";"os_version";"os_build";"kernel";"architecture";
     "sdk_version";"sdk_path";"ocaml_version"];
  if member "os_name"machine<>`String"macOS"
     ||member "architecture"machine<>`String"arm64"then
    fail "qualification machine is not native arm64 macOS";
  (match field "machine" "display_inventory"machine with
   |`Assoc fields->(match List.assoc_opt"SPDisplaysDataType"fields with
      |Some(`List(_::_))->()|_->fail "machine display inventory has no displays")
   |_->fail "machine display inventory is not an object")

let validate_report ?(verify_files=true) report =
  if member "schema" report <> `String qualification_schema then
    fail "report is not an R10 native qualification artifact";
  let protocol = field "report" "protocol" report in
  let profile = string "protocol.profile" (field "protocol" "profile" protocol)
  and width = integer "protocol.width" (field "protocol" "width" protocol)
  and height = integer "protocol.height" (field "protocol" "height" protocol)
  and expected = integer "protocol.samples" (field "protocol" "samples" protocol)
  and warmup_seconds=
    number "protocol.warmup_seconds"(field "protocol" "warmup_seconds"protocol)
  and sample_seconds =
    number "protocol.sample_seconds" (field "protocol" "sample_seconds" protocol)
  in
  if profile<>"release"||width<>640||height<>480||expected<>5
     ||warmup_seconds<>3.||sample_seconds<>30. then
    fail "qualification protocol must be release, 640x480, 5 runs, 3s warmup, 30s sample";
  if member "kind"protocol<>`String"qualification"then
    fail "qualification protocol kind is absent";
  R10_phase0_workload_authority.validate_all~width~height;
  let provenance = field "report" "provenance" report in
  validate_machine provenance;
  let baseline_path =
    string "provenance.baseline_path"
      (field "provenance" "baseline_path" provenance)
  in
  if verify_files then begin
    let baseline_digest = sha256 baseline_path in
    if baseline_digest <> frozen_baseline_sha256 then
      fail "Phase0 baseline digest drift: %s" baseline_digest
  end;
  if member "baseline_sha256" provenance <> `String frozen_baseline_sha256 then
    fail "report baseline digest provenance mismatch";
  if member "workload_commit"provenance<>`String R10_phase0_workload_authority.commit
     ||member "workload_source"provenance<>
       `String R10_phase0_workload_authority.source_path
     ||member "workload_source_sha256"provenance<>
       `String R10_phase0_workload_authority.source_sha256 then
    fail "frozen Phase0 workload provenance mismatch";
  let commit = string "provenance.git_commit" (field "provenance" "git_commit" provenance) in
  if not (canonical_commit commit) then fail "report lacks a canonical git commit";
  if boolean "provenance.git_dirty" (field "provenance" "git_dirty" provenance) then
    fail "qualification report was captured from a dirty source tree";
  let benchmark=string "provenance.benchmark"(field "provenance" "benchmark"provenance)in
  if benchmark<>production_benchmark then fail "qualification used a non-production benchmark";
  let executable_sha = string "provenance.executable_sha256"
      (field "provenance" "executable_sha256" provenance) in
  let protocol_executable=string "provenance.protocol_executable"
      (field "provenance" "protocol_executable"provenance)in
  let protocol_sha = string "provenance.protocol_executable_sha256"
      (field "provenance" "protocol_executable_sha256" provenance) in
  if not(hex64 executable_sha&&hex64 protocol_sha)then
    fail "qualification executable digests are not canonical SHA-256";
  if protocol_executable<>production_protocol_suffix
     &&not(String.ends_with~suffix:("/"^production_protocol_suffix)
       protocol_executable)then
    fail "qualification used a non-production protocol executable";
  if verify_files then begin
    if not(Sys.file_exists benchmark)||sha256 benchmark<>executable_sha then
      fail "benchmark executable digest does not correspond to its path";
    if not(Sys.file_exists protocol_executable)||sha256 protocol_executable<>protocol_sha then
      fail "protocol executable digest does not correspond to its path"
  end;
  ignore(validate_exact_cells report~expected~benchmark~width~height~warmup_seconds
    ~sample_seconds~qualification:true);
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
          check_cell_semantics ~qualification:true ~sample_seconds ~warmup_seconds
            ~profile ~width ~height
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
                if median_ratio > 1.05 then
                  fail "%s/%s %s median regressed %.3fx (maximum 1.05x)"
                    scenario visibility (metric_name metric) median_ratio;
                if p95_ratio > 1.10 then
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
                  ; "passed", `Bool (median_ratio <= 1.05 && p95_ratio <= 1.10)
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

let validate_smoke_report report =
  if member "schema"report<>`String smoke_schema then
    fail "report is not an R10 native smoke artifact";
  let protocol=field "report" "protocol"report in
  if member "kind"protocol<>`String"smoke"then fail "smoke protocol kind is absent";
  let profile=string "protocol.profile"(field "protocol" "profile"protocol)
  and width=integer "protocol.width"(field "protocol" "width"protocol)
  and height=integer "protocol.height"(field "protocol" "height"protocol)
  and expected=integer "protocol.samples"(field "protocol" "samples"protocol)
  and warmup_seconds=number "protocol.warmup_seconds"(field "protocol" "warmup_seconds"protocol)
  and sample_seconds=number "protocol.sample_seconds"(field "protocol" "sample_seconds"protocol)in
  if profile<>"release"||width<>640||height<>480||expected<>1
     ||warmup_seconds<=0.||sample_seconds<=0. then fail "invalid smoke protocol";
  R10_phase0_workload_authority.validate_all~width~height;
  let provenance=field "report" "provenance"report in
  if member "workload_commit"provenance<>`String R10_phase0_workload_authority.commit
     ||member "workload_source_sha256"provenance<>
       `String R10_phase0_workload_authority.source_sha256 then
    fail "smoke workload provenance mismatch";
  let benchmark=string "provenance.benchmark"(field "provenance" "benchmark"provenance)in
  ignore(validate_exact_cells report~expected~benchmark~width~height~warmup_seconds
    ~sample_seconds~qualification:false);
  List.iter(fun scenario->List.iter(fun visibility->
    let samples=samples_for report scenario visibility in
    if List.length samples<>1 then fail "%s/%s smoke cell count drift"scenario visibility;
    check_cell_semantics~qualification:false~sample_seconds~warmup_seconds~profile
      ~width~height scenario visibility samples)visibilities)scenarios;
  if member "summaries"report<>`Null then
    fail "smoke artifacts must not contain qualification summaries"

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
  if not smoke&&(runs<>5||warmup_seconds<>3.||sample_seconds<>30.)then
    fail "R10 qualification requires exactly 5 runs, 3s warmup, and 30s samples";
  if smoke&&(runs<>1||warmup_seconds<=0.||sample_seconds<=0.)then
    fail "R10 smoke requires one positive-duration run per cell";
  if not smoke&&benchmark<>production_benchmark then
    fail "qualification benchmark must be %s"production_benchmark;
  if not dry_run then preflight_benchmark ~profile benchmark;
  if not (Sys.file_exists benchmark) then fail "benchmark does not exist: %s" benchmark;
  if sha256 baseline_path <> frozen_baseline_sha256 then
    fail "Phase0 baseline digest drift";
  List.iter
    (fun scenario ->
      ignore (baseline_runs ~baseline_path ~profile ~width ~height scenario))
    scenarios;
  R10_phase0_workload_authority.validate_all~width~height;
  let commit = if smoke || dry_run then git [ "rev-parse"; "HEAD" ] else clean_commit () in
  let executable_digest = sha256 benchmark in
  let protocol_executable_digest = sha256 Sys.executable_name in
  let machine=if dry_run then `Null else machine_facts()in
  let samples_json = ref [] in
  for sample_index = 1 to runs do
    List.iter
      (fun scenario ->
        List.iter
          (fun visibility ->
            let command=expected_command~benchmark~width~height~warmup_seconds
              ~sample_seconds scenario visibility in
            let argv=Array.of_list command in
            Printf.printf "[%d/%d] %s/%s\n%!" sample_index runs scenario visibility;
            if dry_run then Printf.printf "  %s\n%!" (String.concat " " (Array.to_list argv))
            else
              let conditions_before=conditions()in
              let raw = capture argv in
              let conditions_after=conditions()in
              samples_json :=
                `Assoc
                  [ "sample_index", `Int sample_index
                  ; "scenario", `String scenario
                  ; "visibility", `String visibility
                  ; "command", `List(List.map(fun value->`String value)command)
                  ; "conditions_before",conditions_before
                  ; "conditions_after",conditions_after
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
        ; "sample_seconds", `Float sample_seconds
        ; "kind",`String(if smoke then"smoke"else"qualification")
        ; "ordering", `String "round-major/scenario-major/visibility-minor"
        ]
    in
    let provisional =
      `Assoc
        [ "schema", `String(if smoke then smoke_schema else qualification_schema)
        ; "protocol", protocol
        ; "provenance",
            `Assoc
              [ "git_commit", `String commit
              ; "git_dirty", `Bool(git["status";"--porcelain=v1";"--untracked-files=all"]<>"")
              ; "benchmark", `String benchmark
              ; "executable_sha256", `String executable_digest
              ; "protocol_executable", `String Sys.executable_name
              ; "protocol_executable_sha256", `String protocol_executable_digest
              ; "baseline_path", `String baseline_path
              ; "baseline_sha256", `String frozen_baseline_sha256
              ; "workload_commit",`String R10_phase0_workload_authority.commit
              ; "workload_source",`String R10_phase0_workload_authority.source_path
              ; "workload_source_sha256",`String R10_phase0_workload_authority.source_sha256
              ; "machine",machine
              ]
        ; "samples", `List (List.rev !samples_json)
        ]
    in
    let report=if smoke then(begin validate_smoke_report provisional;provisional end)else
      let summaries=validate_report provisional in match provisional with
      |`Assoc fields->`Assoc(fields@["summaries",`List summaries])|_->assert false in
    if smoke then validate_smoke_report report else ignore(validate_report report);
    write_json output report;
    Printf.printf "R10 native %s passed: %s\n%!"
      (if smoke then"smoke"else"qualification")output
  end

let synthetic_raw ~scenario ~visibility run =
  let frames = integer scenario (field scenario "frames" run) in
  let work_units,signature=expected_workload scenario in
  let evidence=R10_phase0_workload_authority.runtime_evidence
      (authority_scenario scenario)in
  let upload=if evidence.uploads_full_frame_per_frame then
      Int64.mul(Int64.of_int frames)(Int64.of_int(640*480*4))else 0L in
  let offscreen_setup,offscreen_measurement=match scenario with
    |"basic"->
        `Assoc["frames",`String"1";"draws",`String"4";"passes",`String"1";
          "submissions",`String"1";"uploaded_bytes",`String"1";
          "cache_entries",`Int 1],`Null
    |"canvas"->
        `Assoc["frames",`String"1";"draws",`String"0";"passes",`String"1";
          "submissions",`String"1";"uploaded_bytes",`String"0";
          "cache_entries",`Int 0],
        `Assoc["frames",`String(Int.to_string frames);
          "draws",`String(Int.to_string(frames*5));
          "passes",`String(Int.to_string frames);
          "submissions",`String(Int.to_string frames);
          "uploaded_bytes",`String"1";"cache_entries",`Int 1]
    |_ ->`Null,`Null in
  `Assoc
    [ "backend",`String"real-m1-runtime-next-metal"
    ; "benchmark_identity",`String"runtime-next-production-public-r10"
    ; "profile", `String "release"; "width", `Int 640; "height", `Int 480
    ; "phase0_fps_configuration",`Int 60
    ; "measurement_clock",`String"phase0-prior-dt-fps60-integer-ms"
    ; "timing_buffer_capacity",`Int 16384;"rss_sample_seconds",`Float 1.
    ; "scenario", `String (expected_raw_scenario scenario)
    ; "visibility", `String visibility
    ; "observed_visible", `Bool (visibility = "visible")
    ; "protocol_r11_requested",`Bool true
    ; "warmup_seconds",`Float 3.
    ; "scheduling",`String"duration-bounded"
    ; "semantics_supported", `Bool true; "sample_frames", `Int frames
    ; "wall_seconds", field scenario "wall_seconds" run
    ; "user_seconds", field scenario "user_seconds" run
    ; "system_seconds", field scenario "system_seconds" run
    ; "median_ms", `Float (1000. *. number scenario (field scenario "median_frame_seconds" run))
    ; "p95_ms", `Float (1000. *. number scenario (field scenario "p95_frame_seconds" run))
    ; "promoted_bytes", field scenario "promoted_bytes" run
    ; "peak_sampled_rss_kib", field scenario "peak_sampled_rss_kib" run
    ; "workload_signature", `String signature
    ; "canonical_framebuffer_digest", `String(Digest.to_hex(Digest.string scenario))
    ; "canonical_pixel_source", `String ("candidate-stability-frame-1/" ^ scenario)
    ; "pixel_source",`String("runtime-next-native"^
        (if visibility="hidden"then"-hidden"else"")^"/"^scenario)
    ; "work_units", `Int work_units
    ; "draws",`Int(frames*evidence.draws_per_frame)
    ; "passes",`Int(frames*evidence.passes_per_frame)
    ; "backend_calls",`Int(frames*evidence.submissions_per_frame)
    ; "measurement_upload_bytes",`String(Int64.to_string upload)
    ; "offscreen_setup",offscreen_setup
    ; "offscreen_measurement",offscreen_measurement
    ; "window",`Assoc["logical_width",`Int 640;"logical_height",`Int 480;
        "drawable_width",`Int 640;"drawable_height",`Int 480;
        "pixel_density",`Float 1.;"display_scale",`Float 1.;
        "refresh_hz",`Float 60.;"vsync",`Bool false]
    ; "metal_device",`Assoc["selection",`String"Metal.Device.system_default";
        "name",`String"Apple Test";"registry_id",`String"1";
        "architecture",`String"applegpu_test";"low_power",`Bool false;
        "removable",`Bool false;"unified_memory",`Bool true;
        "recommended_max_working_set_size",`String"1";
        "max_buffer_length",`String"1"]
    ; "metal_lifetime",`Assoc[
        "before",`Assoc["pending",`Int 0;"dropped",`Int 0;
          "live_handles",`Int 0;"total_created",`String"10";
          "total_released",`String"10";"external_deallocations",`String"0";
          "external_deallocation_mismatches",`String"0"];
        "after",`Assoc["pending",`Int 0;"dropped",`Int 0;
          "live_handles",`Int 0;"total_created",`String"20";
          "total_released",`String"20";"external_deallocations",`String"0";
          "external_deallocation_mismatches",`String"0"]]
    ; "native_gpu_counters",`Assoc["status",`String"unsupported";
        "supported",`Bool false]
    ]

let self_test baseline_path =
  if sha256 baseline_path <> frozen_baseline_sha256 then fail "self-test baseline drift";
  let sample_values = ref [] in
  let baselines=List.map(fun scenario->scenario,
    baseline_runs~baseline_path~profile:"release"~width:640~height:480 scenario)scenarios in
  for index=0 to 4 do
    List.iter(fun scenario->
      let runs=List.assoc scenario baselines in
      List.iter(fun visibility->let run=List.nth runs index in
              sample_values :=
                `Assoc
                  [ "sample_index", `Int (index + 1); "scenario", `String scenario
                  ; "visibility", `String visibility
                  ; "command",`List(List.map(fun value->`String value)
                      (expected_command~benchmark:production_benchmark~width:640~height:480
                        ~warmup_seconds:3.~sample_seconds:30. scenario visibility))
                  ; "conditions_before",`Assoc["captured_epoch_seconds",`Float 1.;
                      "power",`String"Now drawing from 'AC Power'";
                      "thermal",`String"nominal"]
                  ; "conditions_after",`Assoc["captured_epoch_seconds",`Float 2.;
                      "power",`String"Now drawing from 'AC Power'";
                      "thermal",`String"nominal"]
                  ; "raw", synthetic_raw ~scenario ~visibility run
                  ]
                :: !sample_values)visibilities)scenarios
  done;
  let report =
    `Assoc
      [ "schema", `String qualification_schema
      ; "protocol", `Assoc
          [ "profile", `String "release"; "width", `Int 640; "height", `Int 480
          ; "samples", `Int 5; "warmup_seconds", `Float 3.
          ; "sample_seconds", `Float 30.;"kind",`String"qualification" ]
      ; "provenance", `Assoc
          [ "git_commit", `String (String.make 40 'a'); "git_dirty", `Bool false
          ; "benchmark",`String production_benchmark
          ; "executable_sha256", `String (String.make 64 'b')
          ; "protocol_executable",`String"_build/default/tools/r10_performance/r10_native_protocol.exe"
          ; "protocol_executable_sha256", `String (String.make 64 'c')
          ; "baseline_path", `String baseline_path
          ; "baseline_sha256", `String frozen_baseline_sha256
          ; "workload_commit",`String R10_phase0_workload_authority.commit
          ; "workload_source",`String R10_phase0_workload_authority.source_path
          ; "workload_source_sha256",`String R10_phase0_workload_authority.source_sha256
          ; "machine",`Assoc["os_name",`String"macOS";"os_version",`String"test";
              "os_build",`String"test";"kernel",`String"test";
              "architecture",`String"arm64";"sdk_version",`String"test";
              "sdk_path",`String"/test";"ocaml_version",`String Sys.ocaml_version;
              "display_inventory",`Assoc["SPDisplaysDataType",
                `List[`Assoc["name",`String"Test Display"]]]]
          ]
      ; "samples", `List (List.rev !sample_values)
      ]
  in
  ignore (validate_report~verify_files:false report);
  let update_assoc key update = function
    |`Assoc fields->`Assoc(List.map(fun(name,value)->
         if name=key then name,update value else name,value)fields)
    |_ -> assert false in
  let update_first_sample update report=update_assoc "samples"(function
    |`List(first::rest)->`List(update first::rest)|_->assert false)report in
  let update_first_raw update report=update_first_sample
      (update_assoc "raw"update)report in
  let replace value _=value in
  let expect_invalid label candidate=
    try ignore(validate_report~verify_files:false candidate);
      fail"self-test accepted %s"label
    with Invalid_report _->()in
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
     ignore (validate_report~verify_files:false broken);
     fail "self-test accepted a missing cell sample"
   with Invalid_report _ -> ());
  expect_invalid "a duplicate cell index"
    (update_first_sample(update_assoc "sample_index"(replace(`Int 2)))report);
  expect_invalid "an unknown cell"
    (update_first_sample(update_assoc "scenario"(replace(`String"unknown")))report);
  expect_invalid "child command drift"
    (update_first_sample(update_assoc "command"(function
       |`List values->`List(values@[`String"--unexpected"])|_->assert false))report);
  expect_invalid "a non-production child backend"
    (update_first_raw(update_assoc "backend"(replace(`String"pretend-metal")))report);
  expect_invalid "renderer counter drift"
    (update_first_raw(update_assoc "draws"(replace(`Int 0)))report);
  expect_invalid "a non-production benchmark"
    (update_assoc "provenance"(update_assoc "benchmark"
       (replace(`String"_build/default/arbitrary.exe")))report);
  expect_invalid "a malformed protocol digest"
    (update_assoc "provenance"(update_assoc "protocol_executable_sha256"
       (replace(`String"not-a-sha")))report);
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
     ignore (validate_report~verify_files:false dirty);
     fail "self-test accepted dirty qualification provenance"
   with Invalid_report _ -> ());
  let wrong_schema=match report with `Assoc fields->`Assoc(List.map(fun(name,value)->
    if name="schema"then name,`String smoke_schema else name,value)fields)|_->assert false in
  (try ignore(validate_report~verify_files:false wrong_schema);
    fail"self-test accepted smoke as qualification"with Invalid_report _->());
  let wrong_duration=match report with `Assoc fields->`Assoc(List.map(fun(name,value)->
    if name="protocol"then match value with `Assoc protocol->name,`Assoc(List.map
      (fun(key,child)->if key="sample_seconds"then key,`Float 29. else key,child)protocol)
      |_->name,value else name,value)fields)|_->assert false in
  (try ignore(validate_report~verify_files:false wrong_duration);
    fail"self-test accepted wrong qualification duration"with Invalid_report _->());
  print_endline "R10 native protocol self-test passed"

let protect action =
  try action () with
  | Invalid_report message ->
      prerr_endline ("R10 native: " ^ message);
      exit 2
