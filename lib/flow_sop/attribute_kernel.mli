(** Cook-time connection between immutable geometry and packed Flow data. *)
val sources : Flow.Eval.value -> int list
val resolve : geometry:(int -> Rdk.Geometry.t option) ->
  Flow.Eval.value -> (Flow.Eval.value, Flow.Diagnostic.t) result
(** Resolve immutable cooked point attributes, shared by kernels and reference probes. *)

val prepare : ?profile:Flow_ir.Profile.t -> ?approx:Flow.Workspace.Paths.t -> ?sink:Flow_ir.sink ->
  sources:int list -> Procedural.Node.t list -> Flow.Eval.value ->
  (Flow_ir.Executor.program, Flow.Diagnostic.t) result
(** Use instantiated, parameter-sensitive topology and elementwise facts to
    prove equal point-array counts before dynamic multi-input fusion. *)

val node : ?state:Flow.Eval.state -> ?reference:bool ->
  ?elems:(string * Flow.Eval.value) list ->
  ?profile:Flow_ir.Profile.t ->
  source:string -> name:string -> values:Flow.Eval.value -> sources:int list ->
  Procedural.Node.t list -> Procedural.Node.t
