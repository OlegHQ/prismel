let () =
  R10_native_protocol_lib.protect (fun () ->
    let benchmark = ref
        "_build/default/tools/runtime_next_native_benchmark/runtime_next_native_benchmark.exe"
    and baseline = ref
        "specification/evidence/gpu_migration/phase0_performance.json"
    and historical_benchmark = ref ""
    and historical_commit = ref "57e1078952b62a39452665cea68d3629530b45b6"
    and output = ref "_build/r10-native-performance.json"
    and profile = ref "release" and width = ref 640 and height = ref 480
    and samples = ref 5 and warmup_seconds = ref 3. and sample_seconds = ref 30.
    and smoke = ref false and dry_run = ref false in
    Arg.parse
      [ "--benchmark", Arg.Set_string benchmark, "native benchmark executable"
      ; "--historical-benchmark", Arg.Set_string historical_benchmark,
          "external Phase0 bench_renderer executable (qualification required)"
      ; "--historical-commit", Arg.Set_string historical_commit,
          "source commit of the external Phase0 executable"
      ; "--baseline", Arg.Set_string baseline, "frozen Phase0 performance JSON"
      ; "--output", Arg.Set_string output, "qualification report"
      ; "--profile", Arg.Set_string profile, "Dune profile (release required)"
      ; "--width", Arg.Set_int width, "logical width (640 required)"
      ; "--height", Arg.Set_int height, "logical height (480 required)"
      ; "--samples", Arg.Set_int samples, "independent runs (5 required)"
      ; "--warmup-seconds", Arg.Set_float warmup_seconds, "per-run warmup"
      ; "--sample-seconds", Arg.Set_float sample_seconds, "per-run measurement"
      ; "--smoke", Arg.Set smoke, "one short run per cell; skip limits/provenance"
      ; "--dry-run", Arg.Set dry_run, "print the 40 qualification child commands"
      ]
      (fun value -> raise (Arg.Bad value))
      "native-only R10 performance protocol";
    let warmup_seconds, sample_seconds =
      if !smoke then 0.02, 0.05 else !warmup_seconds, !sample_seconds
    in
    R10_native_protocol_lib.run ~benchmark:!benchmark
      ~historical_benchmark:!historical_benchmark
      ~historical_commit:!historical_commit ~baseline_path:!baseline
      ~output:!output ~profile:!profile ~width:!width ~height:!height
      ~samples:!samples ~warmup_seconds ~sample_seconds ~smoke:!smoke
      ~dry_run:!dry_run)
