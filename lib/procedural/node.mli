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
  val cook :
    t -> Context.t -> Pdk.Geometry.t array ->
    (cooked, Diagnostic.error) result
end
