(** SOP geometry with an immutable value overlay. Layout remains in the
    editor document; value resolution never changes these literal records. *)
type t = private {
  geometry : Procedural.Edit_graph.t;
  values : Flow.Graph.t;
  drives : Drive.t Port.Map.t;
}
type fragment

val of_geometry : Procedural.Edit_graph.t -> t
val of_parts :
  geometry:Procedural.Edit_graph.t -> values:Flow.Graph.t -> drives:Drive.t Port.Map.t ->
  (t, Flow.Diagnostic.t) result
val validate : t -> (unit, Flow.Diagnostic.t) result
val parameters : t -> node_id:int -> (Port.parameter list, Flow.Diagnostic.t) result
val parameter : t -> Port.t -> (Port.parameter, Flow.Diagnostic.t) result
val output_type : t -> Port.t -> (Flow.Port_type.t, Flow.Diagnostic.t) result
val topological_values : t -> (int list, Flow.Diagnostic.t) result

val add_value_node : ?label:string -> Flow.Value_kind.kind -> t -> (t * int, Flow.Diagnostic.t) result
val relabel : node_id:int -> string -> t -> (t, Flow.Diagnostic.t) result
val with_geometry : Procedural.Edit_graph.t -> t -> (t, Flow.Diagnostic.t) result
val remove_nodes : int list -> t -> (t, Flow.Diagnostic.t) result
val connect_value : source:Port.t -> target:Port.t -> t -> (t, Flow.Diagnostic.t) result
val set_expr : target:Port.t -> Flow.Expr.t -> t -> (t, Flow.Diagnostic.t) result
val clear_drive : target:Port.t -> t -> (t, Flow.Diagnostic.t) result
val disconnect : target:Port.t -> t -> (t, Flow.Diagnostic.t) result
val set_literal : target:Port.t -> Port.literal -> t -> (t, Flow.Diagnostic.t) result
val apply_value_parameters :
  t -> node_id:int -> (string * Param.value) list ->
  (t * Param.effects, Flow.Diagnostic.t) result
val copy_nodes : int list -> t -> (fragment, Flow.Diagnostic.t) result
val paste : fragment -> t -> (t * (int * int) list, Flow.Diagnostic.t) result
(** Copy/paste the induced SOP/value graph. Drives from outside the selection
    become literals; fresh ids remap geometry, values and internal drives. *)
