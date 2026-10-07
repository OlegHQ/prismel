(** Native Scene lowering of Flow's typed deferred drawing plan. Uses the
    workspace evaluator and the environment's fold state. *)
type prepared
val prepare : ?profile:Flow_ir.Profile.t -> ?states:Flow.Eval.value list -> Flow.Eval.plan -> Flow.Eval.value ->
  (prepared, Flow.Diagnostic.t) result
(** Prepare each drawing argument's IR program once for playback or export. *)

val render_prepared : ?state:Flow.Eval.state -> ?reference:bool -> prepared ->
  live:Frame_input.t -> size:int * int -> (Rays.Scene.t, Flow.Diagnostic.t) result
(** The reference option uses the independent evaluator for pixel-parity checks. *)

val render : ?state:Flow.Eval.state -> ?states:Flow.Eval.value list ->
  Flow.Eval.plan -> Flow.Eval.value -> live:Frame_input.t -> size:int * int ->
  (Rays.Scene.t, Flow.Diagnostic.t) result
