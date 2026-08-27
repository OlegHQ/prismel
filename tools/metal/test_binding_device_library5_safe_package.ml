let () =
  Binding_device_library5_safe_package.validate ();
  List.iter
    (fun (site : Binding_device_library5_safe_package.public_site) ->
      if site.module_name = "" || site.value_name = "" then
        invalid_arg ("missing public site for " ^ site.id))
    Binding_device_library5_safe_package.public_sites;
  print_endline "MTLDevice library constructors: exact5 public mapping passed"
