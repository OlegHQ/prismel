let () =
  Binding_device_residual_safe_package.validate ();
  Binding_device_residual11_evidence.validate ();
  List.iter
    (fun (item : Binding_device_residual11_evidence.evidence) ->
      let path = "../../lib/metal/" ^ item.conformance in
      if not (Sys.file_exists path) then
        invalid_arg ("missing conformance source " ^ path))
    Binding_device_residual11_evidence.entries;
  Printf.printf "MTLDevice residual exact11 safe entry/evidence closure passed\n"
