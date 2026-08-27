let field name fields = List.assoc name fields
let run () = Gpu_migration_stability_support.run
  { minutes = 0.; frames = Some 600; sample_every = 100;
    sample_period_seconds = 1.; report = None }
let () =
  let first = run () and second = run () in
  match first, second with
  | `Assoc a, `Assoc b ->
      if field "frames" a <> `Int 600 || field "image_generation" a <> `String "19" then failwith "wrong deterministic workload facts";
      if field "deterministic_hash" a <> field "deterministic_hash" b then failwith "domain-independent workload hash drift";
      if field "final_live_targets" a <> `Int 0 || field "final_live_views" a <> `Int 0 then failwith "live objects after teardown";
      let bounded = Gpu_migration_stability_support.run
        { minutes = 0.; frames = Some 30000; sample_every = 100;
          sample_period_seconds = 0.; report = None } in
      (match bounded with `Assoc fields ->
        if field "sample_observations" fields <> `Int 300 || field "sample_capacity" fields <> `Int 256 then failwith "sample ring metadata drift";
        (match field "samples" fields with `List retained when List.length retained = 256 -> () | _ -> failwith "sample ring is not bounded")
      | _ -> failwith "invalid bounded report");
      print_endline "gpu migration stability: deterministic 2x600-frame smoke passed"
  | _ -> failwith "invalid report"
