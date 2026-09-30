(** Deterministic catalog snapshot shared by the generator and runtime check. *)
val version : int
val generate : ?extra:Catalog.descriptor list -> Procedural.Edit_graph.factory list ->
  (string * string, Flow.Diagnostic.t) result
(** The checked-in S-expression and its digest. *)
