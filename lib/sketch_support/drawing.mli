(** Native Scene lowering of Flow's typed deferred drawing plan. Uses the
    workspace evaluator and the environment's fold state. *)
val render : ?state:Flow.Eval.state -> ?states:Flow.Eval.value list ->
  Flow.Eval.plan -> Flow.Eval.value -> live:Frame_input.t -> size:int * int ->
  (Rays.Scene.t, Flow.Diagnostic.t) result
