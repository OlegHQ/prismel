type t
type output
val create : Rays_execution.gpu -> Pipelines.t -> Emit.msl -> t
val dispatch : t -> Flow_ir.Packed.Private.inputs -> (output, Flow.Diagnostic.t) result
(** Input arrays are borrowed immutable storage. Replace an array when its
    contents change; mutating an uploaded array is unsupported. Each input
    slot retains only its last successfully uploaded array and covered length,
    until buffer replacement or close. Frame/uniform/status writes remain live. *)

val readback : output -> (Flow.Eval.value, Flow.Diagnostic.t) result
val buffer : output -> Ogpu.Backend.buffer option
val count : output -> int
val width : output -> int
val gpu_seconds : output -> float option
val close : t -> unit
module Private : sig
  val buffer_creations : t -> int
  val input_uploads : t -> int
  val input_uploaded_bytes : t -> int
  val status_reads : t -> int
  val readback_bytes : t -> int
  val create_owned : Ogpu.Backend.device -> Ogpu.Backend.queue -> Pipelines.t -> Emit.msl -> t
end
