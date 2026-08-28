type target = Native

val abi_version : int

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

val register : packed -> (unit, error) result
val find : target -> (packed, error) result

module Private : sig
  val reset : unit -> unit
end
