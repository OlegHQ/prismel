val program :
  factories:Procedural.Edit_graph.factory list ->
  ?local_factories:Procedural.Edit_graph.factory list ->
  manifest_digest:string -> Flow.Check.program -> Program.t
(** Rebuild compile-time checked data. The linked catalog must match the
    manifest used by the PPX; a stale digest raises [Invalid_argument]. *)
