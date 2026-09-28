(** Move selected SOP nodes into a shared compound definition. The returned
    network contains one instance; the selected nodes retain their ids inside
    the definition. The caller owns the definition name and canvas layout. *)
val geometry :
  name:string ->
  selected:int list ->
  displayed:int option ->
  definitions:Network.definition Network.String_map.t ->
  Network.t ->
  (Network.t * Network.definition * int, Flow.Diagnostic.t) result

(** Replace one geometry-only compound instance with fresh copies of its
    internal nodes. The returned mapping is [(inner_id, new_id)]; [displayed]
    is the parent display after replacing the instance. *)
val ungroup :
  instance_id:int ->
  displayed:int option ->
  definition:Network.definition ->
  Network.t ->
  (Network.t * (int * int) list * int option, Flow.Diagnostic.t) result
