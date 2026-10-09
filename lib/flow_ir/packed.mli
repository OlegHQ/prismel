(** Specialized numeric packed maps, loops and reductions with scalar registers
    in 1,024-element blocks. Accumulators retain reference evaluation order. *)
type t
type binary = Flow.Packed_ops.binary = Add | Sub | Mul | Div | Mod | Pow | Min | Max | Lt | Le | Gt | Ge | Eq | And | Or
type unary = Flow.Packed_ops.unary = Sin | Cos | Sqrt | Abs | Not
type instruction = Const of float | Input of int * int * int
  | Uniform of int * int | Frame of string | Accumulator of int
  | Binary of binary * int * int | Unary of unary * int
  | Noise3 of int * int * int * int * int | Select of int * int * int
type origin = Flow.Workspace.path * int list
type count_source = Flow.Eval.residual -> Flow.Workspace.term -> origin option
(** Hosts may prove equal source cardinality from instantiated domain facts.
    [None] retains a materialization boundary for dynamic multi-input maps. *)

val compile_result : ?fusion:bool -> ?count_source:count_source ->
  Flow.Eval.residual -> Flow.Workspace.term -> (t, Flow.Diagnostic.t list) Stdlib.result
(** The first actual compilation refusal, with its source location. Declined
    fusion retains a valid unfused program and is not a refusal. *)

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

val gpu_refusals : t -> Flow.Diagnostic.t list
(** Pure form restrictions shared by placement, display execution and emission.
    Constants/noise are checked only when reachable from outputs; ordered
    accumulators are refused even when unreachable. *)

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

module Private : sig
  val output_reachable : t -> bool array
  (** Fresh instruction mask used by GPU qualification and code generation. *)

  type view = {code : instruction array; widths : int array; output : int array;
    uniform_widths : int array; collecting : bool; zipped : bool; skip : int array}
  val view : t -> view
  (* Borrowed immutable arrays for downstream compilation. *)
  type inputs = {arrays : float array array; uniforms : float array array;
    frame : float array; count : int}
  val prepare : ?state:Flow.Eval.state -> ?elems:(string * Flow.Eval.value) list ->
    ?resolve:(Flow.Eval.value -> (Flow.Eval.value, Flow.Diagnostic.t) result) ->
    ?measure:((unit -> float) * (t -> seconds:float -> reference:bool -> unit)) ->
    t -> live:Flow.Eval.live -> (inputs, Flow.Diagnostic.t) result
end
