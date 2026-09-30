(** Immutable editable representation of a procedural network.

    [Graph.t] remains the compiled, cookable DAG. This document can also hold
    disconnected input slots and nodes outside the current display path, then
    compile any valid node back to an ordinary [Graph.t]. It owns topology
    only; editor positions, selection, menus, and cooking belong to UI layers. *)

type t
type fragment
type input_requirement = Required | Optional | Rest
(** [Rest] is only valid last: the slot repeats, so a node holds any number of
    inputs at least the slot count.  The first rest input is required, the
    others optional; extras are named [name_2], [name_3], ... (see
    {!node_slot_names}).  [connect] one past the last input appends one. *)
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
  bypass : bool;
}

val of_graph : Graph.t -> t
val empty : t
(** No nodes; build it up with [add_node] so every node keeps its factory. *)

val root : t -> int option
val set_root : int -> t -> (t, string) result
val inspect : t -> node_info list
val find : t -> node_id:int -> Node.t option
val inputs : t -> node_id:int -> int option array option
val node_slot_names : t -> node_id:int -> string list option
(** Input names retained by the entry's factory, or canonical [in0], [in1], …
    for a graph imported from code. *)

val set_bypass : t -> node_id:int -> bool -> (t, string) result
(** Bypass cooking through slot 0, or empty geometry without that slot.
    Other inputs are ignored. Wiring and literal parameters are retained. *)

val is_bypassed : t -> node_id:int -> bool

val node_factory_key : t -> node_id:int -> string option
val node_factory_fields : t -> node_id:int -> Parameter.field_view list
val node_factory_output_fields : t -> node_id:int -> Parameter.field_view list
(** The catalog factory a node was added from; [None] for nodes that came from
    a code graph ([of_graph]). *)

(** Compile the document root, or a specific display node. Disconnected slots,
    missing references, and cycles are reported without changing the document. *)
val compile : t -> (Graph.t, string) result
val compile_node : t -> node_id:int -> (Graph.t, string) result

(** Every node of the document compiled once. Pass the previous result to
    reuse each node whose entry and compiled inputs are physically unchanged,
    so a parameter edit rebuilds only the edited node and its consumers. *)
type compiled
val compile_all : ?previous:compiled -> t -> compiled
val compiled_node : compiled -> node_id:int -> (Graph.t, string) result

(** Replace only the node payload. Its logical id and input arity must match. *)
val replace_node : Node.t -> t -> (t, string) result
(* Retarget a factory-backed node to an optional-input factory with the same
   operation, preserving its id and label. By default arity is unchanged and
   wiring stays at each index. [preserve_wires_by_name] follows slot names,
   allowing optional slots to be added or disconnected slots to be removed.
   Callers update path-keyed metadata on rename. *)
val rebind_factory :
  ?preserve_wires_by_name:bool -> node_id:int -> factory -> t ->
  (t, string) result
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

val subgraph : int list -> t -> t
(* Retain selected entries with their logical ids and internal connections;
   disconnect inputs from outside the selection. Used when moving a selection
   into a compound definition. *)

(** Remove the selection, reconnecting every consumer to the source of each
    removed node's primary slot. Selected chains resolve to their first
    surviving source. The display root follows that source when removed. *)
val dissolve_nodes : int list -> t -> t

val connect : source:int -> consumer:int -> input_index:int -> t ->
  (t, string) result
val disconnect : consumer:int -> input_index:int -> t -> (t, string) result

(** Copy a selected induced subgraph. Connections to nodes outside the
    selection become disconnected slots. Pasting allocates fresh logical node
    IDs, retains internal wiring, and returns the old-to-new ID mapping. *)
val copy_nodes : int list -> t -> (fragment, string) result
val paste : ?ids:(int * int) list -> fragment -> t -> (t * (int * int) list, string) result
(* [ids] fixes the old-to-new logical ids when inlining a compound. It must
   cover the fragment exactly with distinct, unused positive ids. *)

(** Atomically insert a node's primary slot on a connection. Extra slots start
    disconnected. Sources with no input slot cannot be inserted. *)
val insert_on_connection :
  ?factory:factory -> connection -> Node.t -> t -> (t, string) result

val factory :
  ?operation:string ->
  ?slots:string list ->
  ?fields:Parameter.field_view list ->
  ?output_fields:Parameter.field_view list ->
  key:string ->
  label:string ->
  category:string list ->
  arity:int ->
  (Node.t list -> Node.t) ->
  factory
val factory_slots :
  ?operation:string ->
  ?slots:string list ->
  ?fields:Parameter.field_view list ->
  ?output_fields:Parameter.field_view list ->
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
val factory_fields : factory -> Parameter.field_view list
val factory_arity : factory -> int
val factory_inputs : factory -> input_requirement list

val factory_slot_names : factory -> string list
(** Named geometry inputs, in slot order; defaults to [in0], [in1], … . *)

val factory_ready : factory -> Node.t option list -> bool
val instantiate : factory -> Node.t list -> (Node.t, string) result
val instantiate_optional : factory -> Node.t option list -> (Node.t, string) result
