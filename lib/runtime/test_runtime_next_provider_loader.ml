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
  ignore (Result.get_ok (Runtime_next_provider_loader.ensure ~load Native));
  ignore (Result.get_ok (Runtime_next_provider_loader.ensure ~load Native));
  if !loads <> [Native] then failwith "native provider was not loaded exactly once";
  Private.reset ();
  (match Runtime_next_provider_loader.ensure ~load:(fun _ -> Ok ()) Native with
   | Error (Registration_failed (Missing_target Native)) -> ()
   | _ -> failwith "loader accepted a plugin that did not register");
  (match Runtime_next_provider_loader.ensure ~load:(fun _ -> Error "missing") Native with
   | Error (Load_failed {target=Native;message="missing"}) -> ()
   | _ -> failwith "loader failure changed");
  print_endline "runtime-next selected provider loader: once/missing/failure"
