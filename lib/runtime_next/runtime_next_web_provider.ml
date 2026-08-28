include Runtime_next_web

module Descriptor = struct
  let abi_version = Runtime_next_provider.abi_version
  let target = Runtime_next_provider.Web
  let name = "runtime-next-web"
end

let install () =
  match Runtime_next_provider.find Descriptor.target with
  | Ok (Runtime_next_provider.Pack (module Provider)) when Provider.name=Descriptor.name -> Ok ()
  | _ -> Runtime_next_provider.register
      (Runtime_next_provider.Pack (module Descriptor : Runtime_next_provider.S))

let () = ignore (install ())
