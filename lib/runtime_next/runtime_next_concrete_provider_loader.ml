let string_of_target = function
  | Runtime_next_provider.Native -> "native"
  | Runtime_next_provider.Headless -> "headless"
  | Runtime_next_provider.Web -> "web"

let load target =
  let result =
    match target with
    | Runtime_next_provider.Native -> Runtime_next_native_provider.install ()
    | Runtime_next_provider.Headless -> Runtime_next_headless_provider.install ()
    | Runtime_next_provider.Web -> Runtime_next_web_provider.install ()
  in
  Result.map_error
    (fun _ -> "could not register the " ^ string_of_target target ^ " provider")
    result

let ensure target = Runtime_next_provider_loader.ensure ~load target
