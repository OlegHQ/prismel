let minutes = ref 0.1 and frames = ref None and sample_every = ref 60 and report = ref None
let set_frames value = frames := Some value
let () =
  Arg.parse [ "--minutes", Arg.Set_float minutes, "wall-clock run duration";
    "--frames", Arg.Int set_frames, "deterministic frame limit (CI/testing)";
    "--sample-every", Arg.Set_int sample_every, "counter/RSS sampling interval";
    "--report", Arg.String (fun value -> report := Some value), "JSON output path" ]
    (fun value -> raise (Arg.Bad ("unexpected argument: " ^ value))) "gpu_migration_stability";
  ignore (Gpu_migration_stability_support.run
    { minutes = !minutes; frames = !frames; sample_every = !sample_every;
      sample_period_seconds = 1.; report = !report })
