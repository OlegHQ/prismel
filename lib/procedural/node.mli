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
val cook_mode : t -> cook_mode
val dependencies : t -> Context.Dependencies.t
val inputs : t -> t list
val trace : t -> Diagnostic.trace

(** Concrete, type-erased inspector fields owned by this node instance. Empty
    for legacy/unexposed nodes. *)
val parameter_fields : t -> Parameter.field_view list
val has_parameters : t -> bool

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
  type input_policy = All | Only of int
  type cooked = {
    geometry : Pdk.Geometry.t;
    diagnostics : Diagnostic.t list;
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
  val with_inputs : t -> t array -> t
  (* Rebuild a parameterized node against new inputs so input-dependent
     schemas (for example Switch choices) stay current. The logical id is
     retained. Unparameterized nodes behave like [with_inputs]. *)
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
