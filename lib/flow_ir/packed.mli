(** A specialized packed map with scalar registers in 1,024-element blocks. *)
type t
val compile : Flow.Eval.residual -> Flow.Workspace.term -> t option
(** Unsupported bodies remain on the reference interpreter. *)

val static_count : t -> int option
val force : ?state:Flow.Eval.state -> ?elems:(string * Flow.Eval.value) list ->
  t -> live:Flow.Eval.live -> (Flow.Eval.value, Flow.Diagnostic.t) result
val reference : ?state:Flow.Eval.state -> ?elems:(string * Flow.Eval.value) list ->
  t -> live:Flow.Eval.live -> (Flow.Eval.value, Flow.Diagnostic.t) result
