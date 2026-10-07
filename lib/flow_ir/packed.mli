(** Specialized numeric packed maps, loops and reductions with scalar registers
    in 1,024-element blocks. Accumulators retain reference evaluation order. *)
type t
type origin = Flow.Workspace.path * int list
type count_source = Flow.Eval.residual -> Flow.Workspace.term -> origin option
(** Hosts may prove equal source cardinality from instantiated domain facts.
    [None] retains a materialization boundary for dynamic multi-input maps. *)

val compile : ?fusion:bool -> ?count_source:count_source ->
  Flow.Eval.residual -> Flow.Workspace.term -> t option
(** Unsupported bodies remain on the reference interpreter. Fusion defaults to
    true; false retains intermediate arrays for parity checks and profiling. *)

val compile_template : ?count_source:count_source -> Flow.Eval.residual -> Flow.Workspace.term -> t option
val rebind : t -> Flow.Eval.residual -> t option
(** A frame-fold template keeps captures as uniforms and reuses its register
    code with the next step's immutable bindings. A changed function body or a
    fused lexical scope requires a fresh specialization. *)

val static_count : t -> int option
val count_origin : t -> origin option
val elementwise : t -> bool
(** False for sums and accumulator steps; they must not fuse as independent elements. *)

val stage_count : t -> int
(** Number of packed stages executed in this register program without intermediate arrays. *)

val provenance : t -> (int * Flow.Workspace.path * int list) list
(** Graph instance, authored site and iteration tuple for every fused stage. *)

val site : t -> int * Flow.Workspace.path * int list
(** The consuming stage, where the group's single timing belongs. *)

val force : ?state:Flow.Eval.state -> ?elems:(string * Flow.Eval.value) list ->
  ?resolve:(Flow.Eval.value -> (Flow.Eval.value, Flow.Diagnostic.t) result) ->
  ?measure:((unit -> float) * (t -> seconds:float -> reference:bool -> unit)) ->
  t -> live:Flow.Eval.live -> (Flow.Eval.value, Flow.Diagnostic.t) result
val reference : ?state:Flow.Eval.state -> ?elems:(string * Flow.Eval.value) list ->
  ?resolve:(Flow.Eval.value -> (Flow.Eval.value, Flow.Diagnostic.t) result) ->
  t -> live:Flow.Eval.live -> (Flow.Eval.value, Flow.Diagnostic.t) result
