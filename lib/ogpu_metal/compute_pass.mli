type binding = { id:int64; index:int; buffer:Buffer.t }
type t
val create : Device.t -> Ogpu.Compute_pass.t -> pipeline:Pipeline.t ->
  bindings:binding list -> (t,Ogpu.Error.t) result
module Private : sig
  val retain : t -> ((unit -> unit) list,Ogpu.Error.t) result
  val encode : Metal.Command_buffer.t -> t -> (unit,Ogpu.Error.t) result
end
