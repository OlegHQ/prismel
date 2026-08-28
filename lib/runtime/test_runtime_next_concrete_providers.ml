let get = function Ok value -> value | Error error -> failwith (Ogpu.Error.to_string error)
let provider_name target =
  match Runtime_next_provider.find target with
  | Ok (Runtime_next_provider.Pack (module Provider)) -> Provider.name
  | Error _ -> failwith "provider was not installed"

let () =
  ignore (Runtime_next_native_provider.install ());
  if provider_name Runtime_next_provider.Native <> "runtime-next-metal" then
    failwith "provider identity drift";
  print_endline "runtime-next concrete provider: native identity"
