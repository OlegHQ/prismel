let get = function Ok value -> value | Error error -> failwith (Ogpu.Error.to_string error)
let provider_name target =
  match Runtime_next_provider.find target with
  | Ok (Runtime_next_provider.Pack (module Provider)) -> Provider.name
  | Error _ -> failwith "provider was not installed"

let () =
  ignore (Runtime_next_native_provider.install ());
  ignore (Runtime_next_headless_provider.install ());
  ignore (Runtime_next_web_provider.install ());
  if provider_name Runtime_next_provider.Native <> "runtime-next-metal"
     || provider_name Runtime_next_provider.Headless <> "runtime-next-headless"
     || provider_name Runtime_next_provider.Web <> "runtime-next-web" then
    failwith "provider identity drift";
  let headless = get (Runtime_next_headless_provider.create ~logical_width:2
      ~logical_height:2 ~drawable_width:2 ~drawable_height:2) in
  get (Runtime_next_headless_provider.destroy headless);
  let web = get (Runtime_next_web_provider.create ~logical_width:2
      ~logical_height:2 ~drawable_width:2 ~drawable_height:2 ()) in
  get (Runtime_next_web_provider.destroy web);
  print_endline "runtime-next concrete providers: native identity + headless/web lifecycle"
