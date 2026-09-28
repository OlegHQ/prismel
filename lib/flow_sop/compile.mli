(** Inline compound instances into an ordinary SOP/value network before
    value resolution and procedural compilation. Returned compiled ids must be
    saved with the document. [allocate:false] rejects an internal node whose
    compiled id is missing, for use by the cook path. *)
val flatten :
  ?allocate:bool ->
  definitions:Network.definition Network.String_map.t ->
  compiled_ids:int Instance_path.Map.t ->
  Network.t ->
  (Network.t * int Instance_path.Map.t, Flow.Diagnostic.t) result
