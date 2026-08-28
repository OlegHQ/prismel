type target = Native | Headless | Web

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

let providers : packed option array = Array.make 3 None
let index = function Native -> 0 | Headless -> 1 | Web -> 2

let register (Pack ((module Provider) as provider)) =
  if Provider.abi_version <> abi_version then
    Error (Abi_mismatch { name=Provider.name; expected=abi_version;
      actual=Provider.abi_version })
  else
    let slot = index Provider.target in
    match providers.(slot) with
    | Some _ -> Error (Duplicate_target Provider.target)
    | None -> providers.(slot) <- Some (Pack provider); Ok ()

let find target =
  match providers.(index target) with
  | Some provider -> Ok provider
  | None -> Error (Missing_target target)

module Private = struct
  let reset () = Array.fill providers 0 (Array.length providers) None
end
