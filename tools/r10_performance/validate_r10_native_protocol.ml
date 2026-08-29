let () =
  R10_native_protocol_lib.protect (fun () ->
    let path = ref None in
    Arg.parse [] (fun value -> path := Some value)
      "validate_r10_native_protocol REPORT.json";
    let report =
      R10_native_protocol_lib.read_json
        (match !path with Some path -> path | None -> raise (Arg.Bad "missing report"))
    in
    ignore (R10_native_protocol_lib.validate_report report);
    print_endline "R10 native report validation passed")
