open Runtime_next_provider

let provider target name =
  let module Provider = struct
    let abi_version = Runtime_next_provider.abi_version
    let target = target
    let name = name
  end in
  Pack (module Provider : S)

let () =
  Private.reset ();
  let loads = ref [] in
  let load target = loads := target :: !loads; register (provider target "loaded")
    |> Result.map_error (fun _ -> "registration failed") in
  ignore (Result.get_ok (Runtime_next_provider_loader.ensure ~load Web));
  ignore (Result.get_ok (Runtime_next_provider_loader.ensure ~load Web));
  if !loads <> [Web] then failwith "selected provider was not loaded exactly once";
  Private.reset ();
  (match Runtime_next_provider_loader.ensure ~load:(fun _ -> Ok ()) Headless with
   | Error (Registration_failed (Missing_target Headless)) -> ()
   | _ -> failwith "loader accepted a plugin that did not register");
  (match Runtime_next_provider_loader.ensure ~load:(fun _ -> Error "missing") Native with
   | Error (Load_failed {target=Native;message="missing"}) -> ()
   | _ -> failwith "loader failure changed");
  print_endline "runtime-next selected provider loader: once/missing/failure"
