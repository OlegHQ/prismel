(** Validation glue, linked only by workspace checks. Uses the caller's actual catalog. *)
val check : ?directory:string -> factories:Procedural.Edit_graph.factory list ->
  name:string -> Editor_document.Workspace_doc.t -> unit
(** Compare all plan arguments, instances, results, states and records through
    IR/reference at four times and one/eight domains. A directory also compares
    authored geometry payloads and native pixels of every SOP/drawing result. *)
