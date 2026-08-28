type target = Native

let abi_version = 1

module type S = sig
  val abi_version : int
  val target : target
  val name : string
end

type packed = Pack : (module S) -> packed

type error =
  | Abi_mismatch of { name : string; expected : int; actual : int }
  | Duplicate_target of target
  | Missing_target of target

let registered_provider : packed option ref = ref None

let register (Pack ((module Provider) as provider)) =
  if Provider.abi_version <> abi_version then
    Error (Abi_mismatch { name=Provider.name; expected=abi_version;
      actual=Provider.abi_version })
  else
    match !registered_provider with
    | Some _ -> Error (Duplicate_target Provider.target)
    | None -> registered_provider := Some (Pack provider); Ok ()

let find target =
  match !registered_provider with
  | Some provider -> Ok provider
  | None -> Error (Missing_target target)

module Private = struct
  let reset () = registered_provider := None
end
