(** Immutable procedural DAG nodes. Shared node values represent shared graph
    subgraphs. *)

type cook_mode =
  | Generator
  | Duplicate_input of int
  | In_place of int
  | Instance_input of int
  | Passthrough of int
  | Generic

type t

val id : t -> int
val label : t -> string
val operation : t -> string
val version : t -> int
val parameters : t -> string

(** [Parameter.cook_key] of the attached schema values, computed once when
    the node is parameterized, or [""] for an unparameterized node. Session
    cache identity includes it next to [parameters], so every cook-impact
    schema field participates in the key. *)
val parameter_key : t -> string
val cook_mode : t -> cook_mode
val dependencies : t -> Context.Dependencies.t
val inputs : t -> t list
val trace : t -> Diagnostic.trace

(** Concrete, type-erased inspector fields owned by this node instance. Empty
    for legacy/unexposed nodes. *)
val parameter_fields : t -> Parameter.field_view list
val has_parameters : t -> bool

val relabel : string -> t -> t
(** The same node (id, parameters, cook identity) under a new display label;
    a blank label is ignored. *)

(** Attach a typed immutable parameter record and its pure reconstruction
    function to a node. This is the public extension point for custom SOPs.
    Standard catalog SOPs use the same mechanism. The reconstruction receives
    the stable node label and current graph inputs. *)
val parameterize :
  schema:'parameters Parameter.schema ->
  values:'parameters ->
  rebuild:(label:string -> inputs:t list -> 'parameters -> t) ->
  t ->
  t

(** Apply inspector writes to this node only. Cook-affecting changes rebuild
    its operator closure while preserving the logical node id; view/export
    changes update metadata without invalidating cooked geometry. *)
val apply_parameters :
  t ->
  (string * Parameter.value) list ->
  (t * Parameter.effects, string) result

module Private : sig
  val fresh_id : unit -> int
  val reserve_id : int -> (unit, string) result
  (** Share the logical id allocator with value nodes, including loaded ids. *)

  val restore_id : int -> t -> (t, string) result
  (** Restore a saved logical id and reserve it in the shared allocator. *)

  type input_policy = All | Only of int
  type cooked = {
    geometry : Pdk.Geometry.t;
    diagnostics : Diagnostic.t list;
    instances : Prismel_math.Mat4.t array option;
    (** Packed: [geometry] is a prototype drawn at these transforms. *)
  }

  val make :
    ?label:string ->
    operation:string ->
    version:int ->
    parameters:string ->
    cook_mode:cook_mode ->
    dependencies:Context.Dependencies.t ->
    ?input_policy:input_policy ->
    inputs:t array ->
    (node_id:int -> Context.t -> Pdk.Geometry.t array ->
     (cooked, Diagnostic.error) result) ->
    t

  val input_policy : t -> input_policy
  val input_array : t -> t array
  (* Rebuild a parameterized node against new inputs so input-dependent
     schemas (for example Switch choices) stay current. The logical id is
     retained. Unparameterized nodes only swap their inputs. *)
  val rebuild_with_inputs : t -> t array -> t
  (* Clone a node with a fresh logical id. Parameter values and operator
     metadata are preserved and input-dependent schemas are rebuilt. *)
  val clone_with_inputs : t -> t array -> t
  (* Retain a document node's logical identity and label on a freshly rebuilt
     operator whose physical input list may differ because optional slots were
     connected or disconnected. *)
  val adopt_identity : source:t -> t -> t
  val cook :
    t -> Context.t -> Pdk.Geometry.t array ->
    (cooked, Diagnostic.error) result
end
