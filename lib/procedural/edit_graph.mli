(** Immutable editable representation of a procedural network.

    [Graph.t] remains the compiled, cookable DAG. This document can also hold
    disconnected input slots and nodes outside the current display path, then
    compile any valid node back to an ordinary [Graph.t]. It owns topology
    only; editor positions, selection, menus, and cooking belong to UI layers. *)

type t
type fragment
type input_requirement = Required | Optional
type factory

type connection = {
  source : int;
  consumer : int;
  input_index : int;
}

type node_info = {
  node : Node.t;
  id : int;
  label : string;
  operation : string;
  version : int;
  parameters : string;
  cook_mode : Node.cook_mode;
  dependencies : Context.Dependencies.t;
  inputs : int option array;
  has_parameters : bool;
}

val of_graph : Graph.t -> t
val root : t -> int option
val set_root : int -> t -> (t, string) result
val inspect : t -> node_info list
val find : t -> node_id:int -> Node.t option
val inputs : t -> node_id:int -> int option array option
val connections : t -> connection list

(** Compile the document root, or a specific display node. Disconnected slots,
    missing references, and cycles are reported without changing the document. *)
val compile : t -> (Graph.t, string) result
val compile_node : t -> node_id:int -> (Graph.t, string) result

(** Replace only the node payload. Its logical id and input arity must match. *)
val replace_node : Node.t -> t -> (t, string) result
val apply_parameters :
  t ->
  node_id:int ->
  (string * Parameter.value) list ->
  (t * Parameter.effects, string) result

(** Add a node. By default its existing node inputs are adopted when those ids
    already belong to the document; other slots start disconnected. *)
val add_node :
  ?inputs:int option array -> ?factory:factory ->
  Node.t -> t -> (t, string) result
val remove_nodes : int list -> t -> t
val connect : source:int -> consumer:int -> input_index:int -> t ->
  (t, string) result
val disconnect : consumer:int -> input_index:int -> t -> (t, string) result

(** Copy a selected induced subgraph. Connections to nodes outside the
    selection become disconnected slots. Pasting allocates fresh logical node
    IDs, retains internal wiring, and returns the old-to-new ID mapping. *)
val copy_nodes : int list -> t -> (fragment, string) result
val paste : fragment -> t -> (t * (int * int) list, string) result

(** Atomically insert a one-input node on an existing connection. *)
val insert_on_connection :
  ?factory:factory -> connection -> Node.t -> t -> (t, string) result

val factory :
  ?operation:string ->
  key:string ->
  label:string ->
  category:string list ->
  arity:int ->
  (Node.t list -> Node.t) ->
  factory
val factory_slots :
  ?operation:string ->
  key:string ->
  label:string ->
  category:string list ->
  inputs:input_requirement list ->
  (Node.t option list -> Node.t) ->
  factory
val factory_key : factory -> string
val factory_operation : factory -> string
val factory_label : factory -> string
val factory_category : factory -> string list
val factory_arity : factory -> int
val factory_inputs : factory -> input_requirement list
val factory_ready : factory -> Node.t option list -> bool
val instantiate : factory -> Node.t list -> (Node.t, string) result
val instantiate_optional : factory -> Node.t option list -> (Node.t, string) result
