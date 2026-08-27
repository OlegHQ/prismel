let sample ~target ~scenario =
  `Assoc
    [ "target", `String target
    ; "scenario", `String scenario
    ; "profile", `String "release"
    ; "resolution", `Assoc [ "logical_width", `Int 64; "logical_height", `Int 64 ]
    ; "timing",
      `Assoc
        [ "wall_seconds", `Float 1.
        ; "median_frame_seconds", `Float 0.01
        ; "p95_frame_seconds", `Float 0.011
        ; "p99_frame_seconds", `Float 0.012
        ]
    ; "memory",
      `Assoc
        [ "allocated_bytes_per_frame", `Float 12.
        ; "promoted_bytes_per_frame", `Float 0.
        ]
    ; "work", `Assoc [ "frame_count", `Int 100; "work_units", `Int 42 ]
    ; "equivalence",
      `Assoc
        [ "workload_signature", `String (scenario ^ "-work")
        ; "semantics_supported", `Bool true
        ; "pixel_hash", `String (target ^ "-" ^ scenario ^ "-pixels")
        ; "pixel_authority", `String ("phase0/" ^ target ^ "/" ^ scenario)
        ; "pixel_tolerance", `Int (if target = "legacy" then 0 else 3)
        ]
    ]

let report samples =
  `Assoc
    [ "protocol",
      `Assoc
        [ "samples", `Int 1; "profile", `String "release"
        ; "width", `Int 64; "height", `Int 64
        ]
    ; "samples", `List samples
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
    List.map (fun scenario -> sample ~target ~scenario) scenarios) targets in
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
             "promoted_bytes_per_frame", `Float 0. ])) samples in
      write invalid (report scene3_memory);
      if run Sys.argv.(1) invalid = Unix.WEXITED 0 then
        failwith "Scene3 normalized allocation bypassed equivalence validation";
      print_endline
        "R10 equivalence validator rejects mismatched work including Scene3")
