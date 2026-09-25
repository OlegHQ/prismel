type binding = { id:int64; index:int; buffer:Buffer.t }
type t
val create : Device.t -> Ogpu_core.Compute_pass.t -> pipeline:Pipeline.t ->
  bindings:binding list -> (t,Ogpu_core.Error.t) result
module Private : sig
  val retain : t -> ((unit -> unit) list,Ogpu_core.Error.t) result
  val encode : Metal.Command_buffer.t -> t -> (unit,Ogpu_core.Error.t) result
end
