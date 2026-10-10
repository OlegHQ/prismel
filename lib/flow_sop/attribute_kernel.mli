(** Cook-time connection between immutable geometry and packed Flow data. *)
val sources : Flow.Eval.value -> int list
val resolve : geometry:(int -> Rdk.Geometry.t option) ->
  Flow.Eval.value -> (Flow.Eval.value, Flow.Diagnostic.t) result
(** Resolve immutable cooked point attributes, shared by kernels and reference probes. *)

val source_origins : sources:int list -> Sop.Node.t list ->
  ((int * int) list, Flow.Diagnostic.t) result
(** The ordered source-to-point-origin proof used by [prepare]. *)

val materialized_source : Sop.Node.t -> Sop.Node.t
(** A normal geometry consumer: cooking it through Session expands upstream
    packed instances at the existing input boundary. Retain it with its source. *)

val prepare : ?profile:Flow_ir.Profile.t -> ?approx:Flow.Workspace.Paths.t -> ?sink:Flow_ir.sink ->
  sources:int list -> Sop.Node.t list -> Flow.Eval.value ->
  (Flow_ir.Executor.program, Flow.Diagnostic.t) result
(** Use instantiated, parameter-sensitive topology and elementwise facts to
    prove equal point-array counts before dynamic multi-input fusion. *)

val node : ?state:Flow.Eval.state -> ?reference:bool ->
  ?elems:(string * Flow.Eval.value) list ->
  ?profile:Flow_ir.Profile.t ->
  source:string -> name:string -> values:Flow.Eval.value -> sources:int list ->
  Sop.Node.t list -> Sop.Node.t
