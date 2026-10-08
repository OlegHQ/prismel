type t
type output
val create : Rays_execution.gpu -> Pipelines.t -> Emit.msl -> t
val dispatch : t -> Flow_ir.Packed.Private.inputs -> (output, Flow.Diagnostic.t) result
val readback : output -> (Flow.Eval.value, Flow.Diagnostic.t) result
val buffer : output -> Ogpu.Backend.buffer option
val count : output -> int
val width : output -> int
val gpu_seconds : output -> float option
val close : t -> unit
module Private : sig
  val buffer_creations : t -> int
  val create_owned : Ogpu.Backend.device -> Ogpu.Backend.queue -> Pipelines.t -> Emit.msl -> t
end
