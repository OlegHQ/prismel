(** Adapt the one generated SOP factory registry to the context-generic
    Flow checker/printer descriptor. *)
val of_factories :
  version:int -> Procedural.Edit_graph.factory list ->
  (Flow.Check.catalog, Flow.Diagnostic.t) result
