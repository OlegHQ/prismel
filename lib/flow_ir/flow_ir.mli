(** Specialized, renderer-independent dataflow. The reference evaluator remains
    in [flow]; downstream hosts own catalog cooking and display sinks. *)
module Operators = Operators
module Packed = Packed

type id = Flow.Workspace.path * int list
(** The path includes a graph-instance namespace; provenance retains the authored
    path, so overrides have distinct cardinality origins without moving cards. *)

module Count : sig
  type t = Static of int | Data of id | Unknown
  (** [Data origin] ties a runtime count to its source. Distinct sources and
      unknown counts cannot be fused merely because both are dynamic. *)
end

type rate = Static | Frame | Event
type precision = Exact | Approx
type tier = Interp | Closure | Cpu_kernel | Cooked
type source =
  | Constant of Flow.Eval.value
  | Frame_field of string
  | Input of string
  | State_previous of Flow.Eval.residual
type body =
  | Operation of string
  | Vector
  | Field of string
  | List_value
  | Record_value of string list
  | Struct_value of string * Flow.Ty.t * string list
  | Reference of Flow.Eval.residual
  | Packed_map of Packed.t
  | Readback
type kernel = { body : body; elementwise : bool; requires_exact : bool }
type sink = Display of string | Export | Sop_input | State_seed | Cache_key
type kind =
  | Source of source
  | Kernel of kernel
  | Opaque of string * Flow.Check.kernel_facts option
  | Sink of sink
type edge = { name : string; node : int }
type node = {
  id : id;
  ty : Flow.Ty.t;
  count : Count.t;
  rate : rate;
  precision : precision;
  kind : kind;
  args : edge list;
  scope : int list;
  invariant : bool;
  provenance : id list;
  tier : tier;
}
type t = { nodes : node array; roots : int array; groups : int array array }

type execution = { owner : id; sites : (int * Flow.Workspace.path * int list) list;
  tier : tier; seconds : float }
module Profile : sig
  type t
  val create : clock:(unit -> float) -> t
  val executions : t -> execution list
  (** Immutable snapshot of at most 512 recent groups. Each packed group has
      one timing, excluding input materialization and nested groups. *)
end

val of_evaluation : Flow.Workspace.t -> Flow.Check.catalog -> Flow.Eval.t -> t
(** Build from the specialized plan, residual captures, graph results and folds. *)

val share : t -> t
val hoist : t -> t
val fuse : t -> t
val prune : t -> t
val place : t -> (t, Flow.Diagnostic.t) result
val optimize : t -> (t, Flow.Diagnostic.t) result
(** Each pass retains authored provenance; precision legality precedes placement. *)

module Executor : sig
  type program
  val compile : ?profile:Profile.t -> ?count_source:Packed.count_source -> Flow.Eval.value -> (program, Flow.Diagnostic.t) result
  val graph : program -> t
  val force : ?state:Flow.Eval.state -> ?elems:(string * Flow.Eval.value) list ->
    ?resolve:(Flow.Eval.value -> (Flow.Eval.value, Flow.Diagnostic.t) result) ->
    ?reference:bool -> program -> live:Flow.Eval.live ->
    (Flow.Eval.value, Flow.Diagnostic.t) result
  (** Selected/probed cones use [reference:true]. Unsupported terms keep the
      reference tree walker; supported scalar dataflow uses its operator records.
      Failures rerun the reference for its precise diagnostic. *)
end
