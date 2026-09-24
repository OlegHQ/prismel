let replace name value = function
  | `Assoc fields -> `Assoc ((name, value) :: List.remove_assoc name fields)
  | _ -> failwith "object"

let sample observation rss =
  `Assoc
    [ "observation", `Int observation
    ; "elapsed", `Float (float observation)
    ; "frame", `Int (observation * 600)
    ; "rss_kib", `Int rss
    ; "heap_words", `Int 10
    ; "live_words", `Int 5
    ; "gc_allocated_bytes_since_sample", `Float 100.
    ; "mesh_cache", `Int 81
    ; "pipeline_cache", `Int 48
    ; "runtime_uploaded_bytes", `Intlit "1024"
    ; "retained_plan_entries", `Int 80
    ; "retained_plan_capacity", `Int 256
    ; "retained_plan_builds", `Intlit "80"
    ; "retained_plan_hits", `Intlit (Int64.to_string (Int64.of_int observation))
    ; "retained_plan_misses", `Intlit "80"
    ; "retained_plan_evictions", `Intlit "0"
    ; "metal_live", `Int 3
    ; "metal_pending", `Int 0
    ; "metal_created", `Intlit "100"
    ; "metal_released", `Intlit "97"
    ; "metal_created_since_sample", `Intlit "1"
    ; "metal_released_since_sample", `Intlit "1"
    ; "resident_bytes", `Intlit "4096"
    ]

let report () =
  let commit = String.make 40 'a' in
  let samples = List.init 256 (fun index -> sample (index + 45) 1000) in
  `Assoc
    [ "schema", `Int 5
    ; "qualification", `String "O6-native-30m"
    ; "source_before", `Assoc [ "commit", `String commit; "clean", `Bool true ]
    ; "source_after", `Assoc [ "commit", `String commit; "clean", `Bool true ]
    ; "source_stable_clean", `Bool true
    ; "minutes", `Float 30.
    ; "changing_payload", `Bool true
    ; "resizing", `Bool true
    ; "capturing", `Bool true
    ; "resize_events", `Int 2
    ; "capture_events", `Int 1
    ; "captured_bytes", `Intlit "12288"
    ; "sample_capacity", `Int 256
    ; "observations", `Int 300
    ; "retained", `Int 256
    ; "samples", `List samples
    ; "rss_limit_percent", `Float 5.
    ; "final_window_rss_low_kib", `Int 1000
    ; "final_window_rss_high_kib", `Int 1000
    ; "final_window_rss_range_percent", `Float 0.
    ; "settled_rss_first_half_high_kib", `Int 1000
    ; "settled_rss_second_half_high_kib", `Int 1000
    ; "settled_rss_plateau_slack_kib", `Int 8192
    ; "live_mesh_cache_peak_bound", `Int 81
    ; "pipeline_cache_live_expected", `Int 48
    ; "retained_plan_capacity_expected", `Int 256
    ; "retained_plan_entries_live_expected", `Int 80
    ; "retained_plan_entries_final", `Int 0
    ; "retained_plan_builds", `Intlit "80"
    ; "retained_plan_hits", `Intlit "220"
    ; "retained_plan_misses", `Intlit "80"
    ; "retained_plan_evictions", `Intlit "0"
    ; "live_mesh_cache_final", `Int 0
    ; "pipeline_cache_final", `Int 0
    ; "metal_pending_final", `Int 0
    ; "metal_live_before", `Int 1
    ; "metal_live_after", `Int 1
    ; "metal_created_delta", `Intlit "10"
    ; "metal_released_delta", `Intlit "10"
    ; "metal_resident_bytes_before", `Intlit "1024"
    ; "metal_resident_bytes_after", `Intlit "4096"
    ]

let run validator value =
  let path = Filename.temp_file "o6-native-validator-" ".json" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists path then Sys.remove path)
    (fun () ->
      Yojson.Safe.to_file path value;
      let validator = Unix.realpath validator in
      let process = Unix.create_process validator [| validator; path |]
          Unix.stdin Unix.stdout Unix.stderr in
      match snd (Unix.waitpid [] process) with
      | Unix.WEXITED code -> code = 0
      | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> false)

let () =
  let validator = Sys.argv.(1) in
  let valid = report () in
  if not (run validator valid) then failwith "valid O6 report rejected";
  let bad_samples = List.init 256 (fun index -> sample (index + 44) 1000) in
  let bad_plan_samples =
    match valid with
    | `Assoc fields ->
        (match List.assoc "samples" fields with
         | `List (first :: rest) ->
             (match replace "retained_plan_evictions" (`Intlit "1") first with
              | changed -> `List (changed :: rest))
         | _ -> assert false)
    | _ -> assert false in
  [ replace "minutes" (`Float 29.9) valid
  ; replace "resizing" (`Bool false) valid
  ; replace "source_stable_clean" (`Bool false) valid
  ; replace "retained" (`Int 255) valid
  ; replace "samples" (`List bad_samples) valid
  ; replace "final_window_rss_high_kib" (`Int 1100) valid
  ; replace "settled_rss_second_half_high_kib" (`Int 1001) valid
  ; replace "samples" bad_plan_samples valid
  ; replace "retained_plan_evictions" (`Intlit "1") valid
  ; replace "live_mesh_cache_final" (`Int 1) valid
  ; replace "metal_pending_final" (`Int 1) valid
  ; replace "metal_live_after" (`Int 2) valid
  ; replace "metal_released_delta" (`Intlit "9") valid
  ; replace "metal_resident_bytes_after" (`Intlit "5000") valid
  ]
  |> List.iteri (fun index value ->
    if run validator value then
      failwith (Printf.sprintf "invalid O6 report %d accepted" index));
  print_endline "O6 native validator positive/negative fixtures passed"
