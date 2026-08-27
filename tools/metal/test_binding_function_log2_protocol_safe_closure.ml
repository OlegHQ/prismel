let () =
  let expected =
    [ "protocol:MTLFunctionLog"
    ; "protocol:MTLFunctionLogDebugLocation"
    ]
  in
  if Binding_function_log2_protocol_safe_closure.promotable_ids <> expected
  then failwith "FunctionLog2 protocol provenance drift";
  print_endline "FunctionLog2 protocols: exact2 immutable diagnostic closure"
