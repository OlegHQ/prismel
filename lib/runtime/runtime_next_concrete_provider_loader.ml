let load _target =
  let result = Runtime_next_native_provider.install () in
  Result.map_error
    (fun _ -> "could not register the native provider")
    result

let ensure target = Runtime_next_provider_loader.ensure ~load target
