let sample ?(wall=1.) ?(frames=100) ?(scheduling="duration-bounded") ~target ~scenario () =
  `Assoc
    [ "target", `String target
    ; "scenario", `String scenario
    ; "profile", `String "release"
    ; "resolution", `Assoc [ "logical_width", `Int 64; "logical_height", `Int 64 ]
    ; "timing",
      `Assoc
        [ "wall_seconds", `Float wall
        ; "cpu_seconds", `Float 0.5
        ; "median_frame_seconds", `Float 0.01
        ; "p95_frame_seconds", `Float 0.011
        ; "p99_frame_seconds", `Float 0.012
        ]
    ; "pacing", `Assoc ["scheduling",`String scheduling;
        "scheduled_frame_rate",`Null]
    ; "memory",
      `Assoc
        [ "allocated_bytes_per_frame", `Float 12.
        ; "promoted_bytes_per_frame", `Float 4.
        ; "peak_rss_kib", `Int 1024
        ]
    ; "work", `Assoc [ "frame_count", `Int frames; "work_units", `Int 42 ]
    ; "equivalence",
      `Assoc
        [ "workload_signature", `String (scenario ^ "-work")
        ; "semantics_supported", `Bool true
        ; "pixel_hash", `String (target ^ "-" ^ scenario ^ "-pixels")
        ; "pixel_authority", `String ("phase0/" ^ target ^ "/" ^ scenario)
        ; "pixel_tolerance", `Int (if target = "legacy" then 0 else 3)
        ]
    ]

let baseline target scenario =
  let metric median p95 = `Assoc ["median", `Float median; "p95", `Float p95] in
  `Assoc ["target", `String target; "scenario", `String scenario;
    "authority", `String ("phase0/" ^ target ^ "/" ^ scenario ^ "/performance");
    "profile", `String "release"; "width", `Int 64; "height", `Int 64;
    "metrics", `Assoc ["wall", metric 1. 1.; "frame", metric 0.01 0.011;
      "CPU", metric 0.5 0.5; "promoted", metric 4. 4.; "RSS", metric 1024. 1024.]]

let report ?(sample_count=1) ?(sample_seconds=1.) ?(smoke=false) samples =
  `Assoc
    [ "protocol",
      `Assoc
        [ "samples", `Int sample_count; "profile", `String "release"
        ; "width", `Int 64; "height", `Int 64;
          "sample_seconds",`Float sample_seconds; "smoke", `Bool smoke
        ]
    ; "samples", `List samples
    ; "performance_baselines", `List (List.concat_map (fun target ->
        List.map (baseline target) ["basic";"pxui";"canvas";"scene3"])
        ["headless";"web"])
    ]

let write path json =
  let output = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out output)
    (fun () -> Yojson.Safe.to_channel output json)

let run executable path =
  let pid = Unix.create_process executable [| executable; "--validate"; path |]
      Unix.stdin Unix.stdout Unix.stderr in
  snd (Unix.waitpid [] pid)

let replace_cell ~target ~scenario replace samples =
  let changed = ref false in
  let result = List.map (function
    | `Assoc fields
      when List.assoc_opt "target" fields = Some (`String target)
           && List.assoc_opt "scenario" fields = Some (`String scenario) ->
        changed := true;
        replace fields
    | value -> value) samples in
  if not !changed then failwith "test did not select mismatched cell";
  result

let replace_field name replacement fields =
  `Assoc (List.map (fun (field, value) ->
    if field = name then field, replacement else field, value) fields)

let () =
  if Array.length Sys.argv <> 2 then invalid_arg "protocol executable";
  let targets = [ "runtime-next-native"; "headless"; "web"; "legacy" ]
  and scenarios = [ "basic"; "pxui"; "canvas"; "scene3" ] in
  let samples = List.concat_map (fun target ->
    List.map (fun scenario -> sample ~target ~scenario ()) scenarios) targets in
  let valid = Filename.temp_file "r10-equivalent-" ".json"
  and invalid = Filename.temp_file "r10-inequivalent-" ".json" in
  Fun.protect
    ~finally:(fun () -> Sys.remove valid; Sys.remove invalid)
    (fun () ->
      write valid (report samples);
      let changed = ref false in
      let broken =
        List.map (fun value ->
          match value with
          | `Assoc fields
            when not !changed
                 && List.assoc_opt "target" fields = Some (`String "web")
                 && List.assoc_opt "scenario" fields = Some (`String "basic") ->
              changed := true;
              `Assoc (List.map (fun (name, field) ->
                if name = "equivalence" then
                  name, `Assoc [ "workload_signature", `String "different-work";
                    "semantics_supported", `Bool true;
                    "pixel_hash", `String "web-basic-pixels";
                    "pixel_authority", `String "phase0/web/basic";
                    "pixel_tolerance", `Int 3 ]
                else name, field) fields)
          | value -> value) samples
      in
      if not !changed then failwith "test did not select mismatched cell";
      write invalid (report broken);
      if run Sys.argv.(1) valid <> Unix.WEXITED 0 then
        failwith "equivalent R10 report rejected";
      if run Sys.argv.(1) invalid = Unix.WEXITED 0 then
        failwith "inequivalent R10 report accepted";
      let different_counts = replace_cell ~target:"headless" ~scenario:"basic"
        (replace_field "work" (`Assoc ["frame_count", `Int 137; "work_units", `Int 42])) samples in
      write valid (report different_counts);
      if run Sys.argv.(1) valid <> Unix.WEXITED 0 then
        failwith "duration-bounded target-specific frame counts rejected";
      let unsupported = List.map (function
        | `Assoc fields when List.assoc_opt "target" fields=Some(`String "web")
          && List.assoc_opt "scenario" fields=Some(`String "pxui")->
            `Assoc(List.map(fun(name,field)->if name="equivalence"then
              name,`Assoc["workload_signature",`String"pxui-work";
                "semantics_supported",`Bool false;
                "pixel_hash",`String"web-pxui-pixels";
                "pixel_authority",`String"phase0/web/pxui";
                "pixel_tolerance",`Int 3]else name,field)fields)
        |value->value)samples in
      write invalid(report unsupported);
      if run Sys.argv.(1) invalid=Unix.WEXITED 0 then
        failwith "unsupported descriptor interpreter accepted";
      let scene3_signature = replace_cell ~target:"web" ~scenario:"scene3"
        (replace_field "equivalence"
           (`Assoc [ "workload_signature", `String "different-scene3-work";
             "semantics_supported", `Bool true;
             "pixel_hash", `String "web-scene3-pixels";
             "pixel_authority", `String "phase0/web/scene3";
             "pixel_tolerance", `Int 3 ])) samples in
      write invalid (report scene3_signature);
      if run Sys.argv.(1) invalid = Unix.WEXITED 0 then
        failwith "Scene3 workload mismatch bypassed equivalence validation";
      let scene3_authority = replace_cell ~target:"legacy" ~scenario:"scene3"
        (fun fields ->
          let equivalence = match List.assoc "equivalence" fields with
            | `Assoc values -> `Assoc (List.map (fun (name, value) ->
                if name = "pixel_authority" then
                  name, `String "phase0/headless/scene3"
                else name, value) values)
            | _ -> assert false in
          replace_field "equivalence" equivalence fields) samples in
      write invalid (report scene3_authority);
      if run Sys.argv.(1) invalid = Unix.WEXITED 0 then
        failwith "Scene3 pixel provenance bypassed equivalence validation";
      let scene3_memory = replace_cell ~target:"headless" ~scenario:"scene3"
        (replace_field "memory"
           (`Assoc [ "allocated_bytes_per_frame", `Null;
             "promoted_bytes_per_frame", `Float 4.; "peak_rss_kib", `Int 1024 ])) samples in
      write invalid (report scene3_memory);
      if run Sys.argv.(1) invalid = Unix.WEXITED 0 then
        failwith "Scene3 normalized allocation bypassed equivalence validation";
      let bad_pacing=replace_cell~target:"runtime-next-native"~scenario:"basic"
        (replace_field "work"(`Assoc["frame_count",`Int 0;"work_units",`Int 42]))samples in
      write invalid(report bad_pacing);
      if run Sys.argv.(1) invalid=Unix.WEXITED 0 then
        failwith"empty duration-bounded frame collection accepted";
      let bad_wall=replace_cell~target:"runtime-next-native"~scenario:"basic"
        (replace_field "timing"(`Assoc["wall_seconds",`Float 0.7;
          "cpu_seconds",`Float 0.5;
          "median_frame_seconds",`Float 0.01;"p95_frame_seconds",`Float 0.011;
          "p99_frame_seconds",`Float 0.012]))samples in
      write invalid(report bad_wall);
      if run Sys.argv.(1) invalid=Unix.WEXITED 0 then
        failwith"render-only wall interval accepted as paced wall time";
      let regressed_frame=replace_cell~target:"runtime-next-native"~scenario:"scene3"
        (replace_field "timing" (`Assoc ["wall_seconds",`Float 1.;
          "cpu_seconds",`Float 0.5; "median_frame_seconds",`Float 0.0106;
          "p95_frame_seconds",`Float 0.011; "p99_frame_seconds",`Float 0.012])) samples in
      write invalid(report regressed_frame);
      if run Sys.argv.(1) invalid=Unix.WEXITED 0 then
        failwith"per-scenario 5% median regression accepted";
      let regressed_rss=replace_cell~target:"web"~scenario:"canvas"
        (replace_field "memory" (`Assoc ["allocated_bytes_per_frame",`Float 12.;
          "promoted_bytes_per_frame",`Float 4.; "peak_rss_kib",`Int 1127])) samples in
      write invalid(report ~sample_count:5
        (List.concat [samples; samples; samples; samples; regressed_rss]));
      if run Sys.argv.(1) invalid=Unix.WEXITED 0 then
        failwith"per-scenario 10% p95 RSS regression accepted";
      let missing_cpu=replace_cell~target:"headless"~scenario:"basic"
        (replace_field "timing" (`Assoc ["wall_seconds",`Float 1.;
          "median_frame_seconds",`Float 0.01; "p95_frame_seconds",`Float 0.011;
          "p99_frame_seconds",`Float 0.012])) samples in
      write invalid(report missing_cpu);
      if run Sys.argv.(1) invalid=Unix.WEXITED 0 then
        failwith"missing comparable CPU metric accepted";
      let missing_baselines = match report samples with
        | `Assoc fields -> replace_field "performance_baselines" (`List []) fields
        | _ -> assert false in
      write invalid missing_baselines;
      if run Sys.argv.(1) invalid=Unix.WEXITED 0 then
        failwith"missing target-specific Phase0 baseline accepted";
      let wrong_baseline field value = match report samples with
        | `Assoc fields ->
            let baselines = match List.assoc "performance_baselines" fields with
              | `List (first :: rest) -> `List (replace_field field value
                  (match first with `Assoc values -> values | _ -> assert false) :: rest)
              | _ -> assert false in
            replace_field "performance_baselines" baselines fields
        | _ -> assert false in
      write invalid (wrong_baseline "profile" (`String "dev"));
      if run Sys.argv.(1) invalid=Unix.WEXITED 0 then
        failwith"mismatched Phase0 baseline profile accepted";
      write invalid (wrong_baseline "width" (`Int 640));
      if run Sys.argv.(1) invalid=Unix.WEXITED 0 then
        failwith"mismatched Phase0 baseline resolution accepted";
      let smoke_samples = List.concat_map (fun target ->
        let scheduling, frames =
          if target = "runtime-next-native" || target = "legacy"
          then "duration-bounded", 7 else "fixed-count", 3 in
        List.map (fun scenario -> sample ~wall:0.0556 ~frames ~scheduling
          ~target ~scenario ()) scenarios) targets in
      write valid (report ~sample_seconds:0.05 ~smoke:true smoke_samples);
      if run Sys.argv.(1) valid <> Unix.WEXITED 0 then
        failwith"mixed-scheduling positive-frame smoke rejected";
      let noisy_smoke = replace_cell ~target:"web" ~scenario:"scene3"
        (replace_field "timing" (`Assoc ["wall_seconds",`Float 0.0556;
          "cpu_seconds",`Float 99.; "median_frame_seconds",`Float 99.;
          "p95_frame_seconds",`Float 99.; "p99_frame_seconds",`Float 99.])) smoke_samples in
      write valid (report ~sample_seconds:0.05 ~smoke:true noisy_smoke);
      if run Sys.argv.(1) valid <> Unix.WEXITED 0 then
        failwith"smoke incorrectly enforced performance thresholds";
      print_endline
        "R10 equivalence validator rejects mismatched work including Scene3")
