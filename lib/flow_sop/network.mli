(** SOP geometry with the live arguments of a lowered workspace graph.  Layout and probes
    stay in the editor document; resolution never changes these literal records. *)
module Int_map : Map.S with type key = int

type t = private {
  geometry : Procedural.Edit_graph.t;
  drives : Flow.Eval.value Port.Map.t;
      (** a workspace argument that depends on [t] ({!Flow.Eval.is_live}), evaluated by
          {!Value_lane.resolve} for each time (a scalar, a vec3, a colour text, or a list of vec3
          for a text-encoded list parameter), keyed (node, argument name).  Compare with [==]. *)
}

val of_geometry : Procedural.Edit_graph.t -> t
val with_drives : Flow.Eval.value Port.Map.t -> t -> (t, Flow.Diagnostic.t) result
val validate : t -> (unit, Flow.Diagnostic.t) result
val parameter : t -> Port.t -> (Port.parameter, Flow.Diagnostic.t) result
val relabel : node_id:int -> string -> t -> (t, Flow.Diagnostic.t) result
val with_geometry : Procedural.Edit_graph.t -> t -> (t, Flow.Diagnostic.t) result
val remove_nodes : int list -> t -> (t, Flow.Diagnostic.t) result
