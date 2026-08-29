let () =
  match Array.to_list Sys.argv with
  | [ _; baseline ] -> R10_native_protocol_lib.self_test baseline
  | _ -> failwith "usage: test_r10_native_protocol PHASE0_PERFORMANCE.json"
