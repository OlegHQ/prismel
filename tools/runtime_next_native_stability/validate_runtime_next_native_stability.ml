open Yojson.Safe.Util

let allow_smoke = ref false
let fail format = Printf.ksprintf failwith format
let require condition format = Printf.ksprintf (fun message -> if not condition then failwith message) format
let canonical_commit value = String.length value = 40 && String.for_all (function '0'..'9'|'a'..'f'->true|_->false) value
let int64_field value name =
  match value |> member name with
  | `Int number -> Int64.of_int number
  | `Intlit number -> Int64.of_string number
  | _ -> fail "%s is not an integer" name

let source value name =
  let snapshot = value |> member name in
  let commit = snapshot |> member "commit" |> to_string in
  require (canonical_commit commit) "%s commit is not canonical" name;
  require (snapshot |> member "clean" |> to_bool) "%s is dirty" name;
  commit

let validate path =
  let value = Yojson.Safe.from_file path in
  require (value |> member "schema" |> to_int = 4) "O6 schema drift";
  let qualification = value |> member "qualification" |> to_string in
  let smoke = qualification = "smoke" in
  require (qualification = "O6-native-30m" || (!allow_smoke && smoke))
    "report is not an O6 qualification";
  let minutes = value |> member "minutes" |> to_float in
  if not smoke then require (minutes >= 30.) "O6 run is shorter than 30 minutes";
  if not smoke then begin
    let before = source value "source_before" and after = source value "source_after" in
    require (before = after && (value |> member "source_stable_clean" |> to_bool))
      "O6 source changed during measurement"
  end;
  require (value |> member "sample_capacity" |> to_int = 256)
    "O6 fixed-ring capacity drift";
  let observations = value |> member "observations" |> to_int in
  let retained = value |> member "retained" |> to_int in
  let samples = value |> member "samples" |> to_list in
  require (List.length samples = retained) "O6 retained count disagrees with samples";
  if not smoke then require (observations >= 256 && retained = 256)
    "O6 qualification lacks the final 256 observations";
  let mesh_bound = value |> member "live_mesh_cache_peak_bound" |> to_int in
  let pipeline_expected = value |> member "pipeline_cache_live_expected" |> to_int in
  let parsed = List.map (fun sample ->
    let observation = sample |> member "observation" |> to_int in
    let frame = sample |> member "frame" |> to_int in
    let elapsed = sample |> member "elapsed" |> to_float in
    let rss = sample |> member "rss_kib" |> to_int in
    let resident = int64_field sample "resident_bytes" in
    require (sample |> member "mesh_cache" |> to_int <= mesh_bound)
      "O6 sample mesh cache exceeds its bound";
    require (sample |> member "pipeline_cache" |> to_int = pipeline_expected)
      "O6 sample pipeline cache changed";
    require (sample |> member "metal_pending" |> to_int >= 0)
      "O6 sample pending count is negative";
    require (frame > 0 && elapsed >= 0. && rss > 0 && resident > 0L)
      "O6 sample facts are invalid";
    observation, frame, elapsed, rss, resident) samples in
  let rec ordered = function
    | [] | [_] -> true
    | (o0,f0,t0,_,_) :: ((o1,f1,t1,_,_) :: _ as rest) ->
        o1 = o0 + 1 && f1 > f0 && t1 > t0 && ordered rest
  in
  require (ordered parsed) "O6 retained observations are not consecutive and monotonic";
  if not smoke then begin
    let first,_,_,_,_ = List.hd parsed and last,_,_,_,_ = List.hd (List.rev parsed) in
    require (first = observations - 255 && last = observations)
      "O6 retained ring is not the exact final observation window"
  end;
  require (value |> member "rss_limit_percent" |> to_float = 5.)
    "O6 RSS policy drift";
  let low = value |> member "final_window_rss_low_kib" |> to_int in
  let high = value |> member "final_window_rss_high_kib" |> to_int in
  let tail = List.filteri (fun index _ -> index >= List.length parsed * 3 / 4) parsed in
  let sampled_rss = List.map (fun (_,_,_,rss,_) -> rss) tail in
  let sampled_low = List.fold_left min max_int sampled_rss in
  let sampled_high = List.fold_left max 0 sampled_rss in
  if parsed <> [] then
    require (low = sampled_low && high = sampled_high)
      "O6 final-window RSS bounds disagree with retained samples";
  let recomputed = if low <= 0 then infinity else 100. *. float (high-low) /. float low in
  let recorded = value |> member "final_window_rss_range_percent" |> to_float in
  require (Float.abs (recorded -. recomputed) <= 1e-9)
    "O6 final-window RSS calculation is inconsistent";
  if not smoke then require (recorded <= 5.) "O6 final-window RSS exceeds 5 percent";
  let mesh_cache_final = value |> member "live_mesh_cache_final" |> to_int in
  let pipeline_cache_final = value |> member "pipeline_cache_final" |> to_int in
  let pending_final = value |> member "metal_pending_final" |> to_int in
  let live_before = value |> member "metal_live_before" |> to_int in
  let live_after = value |> member "metal_live_after" |> to_int in
  let created_delta = int64_field value "metal_created_delta" in
  let released_delta = int64_field value "metal_released_delta" in
  let resident_before = int64_field value "metal_resident_bytes_before" in
  let resident_after = int64_field value "metal_resident_bytes_after" in
  require (mesh_cache_final = 0 && pipeline_cache_final = 0)
    "O6 caches survived teardown";
  require (pending_final = 0) "O6 release queue is still pending";
  require (live_before = live_after)
    "O6 live Metal handle count changed";
  require (created_delta = released_delta)
    "O6 native create/release deltas differ";
  require (resident_before > 0L && resident_after > 0L)
    "O6 process resident-byte context is invalid";
  if not smoke then begin
    let residents = List.map (fun (_,_,_,_,resident) -> resident) tail in
    let resident_low = List.fold_left Int64.min Int64.max_int residents in
    let resident_high = List.fold_left Int64.max 0L residents in
    let resident_range =
      100. *. Int64.to_float (Int64.sub resident_high resident_low)
      /. Int64.to_float resident_low
    in
    require (resident_range <= 5.)
      "O6 final-window process resident bytes exceed 5 percent";
    let resident_teardown_limit =
      Int64.add resident_high (Int64.div resident_high 20L)
    in
    require (resident_after <= resident_teardown_limit)
      "O6 teardown process resident bytes exceed the settled window"
  end;
  print_endline "O6 native lifetime/bounds report: valid"

let () =
  let path = ref None in
  Arg.parse ["--allow-smoke",Arg.Set allow_smoke,"accept a non-qualifying smoke report"]
    (fun value -> path := Some value) "validate_runtime_next_native_stability REPORT";
  validate (Option.get !path)
