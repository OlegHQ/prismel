(** SOP geometry with an immutable value overlay. Layout remains in the
    editor document; value resolution never changes these literal records. *)
module Int_map : Map.S with type key = int
module String_map : Map.S with type key = string
type interface_port = {
  name : string;
  ty : Flow.Port_type.t;
  default : Port.literal option;
  label : string;
  soft : (float * float) option;
}
type instance = { definition : string; literals : Param.value String_map.t }
type t = private {
  geometry : Procedural.Edit_graph.t;
  values : Flow.Graph.t;
  drives : Drive.t Port.Map.t;
  (* Only named compound geometry outputs appear here; absent means [geo]. *)
  geometry_outputs : string Port.Map.t;
  instances : instance Int_map.t;
}
and definition = {
  name : string;
  context : Flow.Context.t;
  inputs : interface_port list;
  outputs : interface_port list;
  body : t;
}
type fragment

val of_geometry : Procedural.Edit_graph.t -> t
val of_parts :
  geometry:Procedural.Edit_graph.t -> values:Flow.Graph.t -> drives:Drive.t Port.Map.t ->
  geometry_outputs:string Port.Map.t ->
  instances:instance Int_map.t ->
  (t, Flow.Diagnostic.t) result
val validate : t -> (unit, Flow.Diagnostic.t) result
val parameters : t -> node_id:int -> (Port.parameter list, Flow.Diagnostic.t) result
val parameter : t -> Port.t -> (Port.parameter, Flow.Diagnostic.t) result
val output_type : t -> Port.t -> (Flow.Port_type.t, Flow.Diagnostic.t) result
val outputs : definitions:definition String_map.t -> t -> node_id:int ->
  ((string * Flow.Port_type.t) list, Flow.Diagnostic.t) result
val geometry_source : t -> Port.t -> Port.t option
val topological_values : t -> (int list, Flow.Diagnostic.t) result

val add_value_node : ?label:string -> Flow.Value_kind.kind -> t -> (t * int, Flow.Diagnostic.t) result
val relabel : node_id:int -> string -> t -> (t, Flow.Diagnostic.t) result
val with_geometry : Procedural.Edit_graph.t -> t -> (t, Flow.Diagnostic.t) result
val connect_geometry : source:Port.t -> consumer:int -> input_index:int -> t ->
  (t, Flow.Diagnostic.t) result
val remove_nodes : int list -> t -> (t, Flow.Diagnostic.t) result
val connect_value : source:Port.t -> target:Port.t -> t -> (t, Flow.Diagnostic.t) result
val set_expr : target:Port.t -> Flow.Expr.t -> t -> (t, Flow.Diagnostic.t) result
val set_live : target:Port.t -> Flow.Eval.value -> t -> (t, Flow.Diagnostic.t) result
(* Install a Drive.Live drive (lowering of a time-dependent argument). *)
val clear_drive : target:Port.t -> t -> (t, Flow.Diagnostic.t) result
val disconnect : target:Port.t -> t -> (t, Flow.Diagnostic.t) result
val set_literal : target:Port.t -> Port.literal -> t -> (t, Flow.Diagnostic.t) result
(* Replace an unshared math/value/time source tree with an expression. The
   returned ids are the value nodes removed from the network. *)
val fold : target:Port.t -> t -> (t * int list, Flow.Diagnostic.t) result
(* Expand an expression into math nodes and one shared time node. Each
   placement is [(id, column, row)]; the host maps those relative coordinates
   to its tile spacing. *)
val unfold : target:Port.t -> t -> (t * (int * int * float) list, Flow.Diagnostic.t) result
val apply_value_parameters :
  t -> node_id:int -> (string * Param.value) list ->
  (t * Param.effects, Flow.Diagnostic.t) result
val copy_nodes : int list -> t -> (fragment, Flow.Diagnostic.t) result
val paste : fragment -> t -> (t * (int * int) list, Flow.Diagnostic.t) result
(** Copy/paste the induced SOP/value graph. Drives from outside the selection
    become literals; fresh ids remap geometry, values and internal drives. *)
