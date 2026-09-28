(** Move selected SOP and value nodes into a shared compound definition.
    Geometry and value wires crossing the selection become typed interface
    ports. The returned network contains one instance; selected nodes retain
    their ids inside the definition. The caller owns the canvas layout. *)
val geometry :
  name:string ->
  selected:int list ->
  displayed:int option ->
  definitions:Network.definition Network.String_map.t ->
  Network.t ->
  (Network.t * Network.definition * int, Flow.Diagnostic.t) result

(** Replace one compound instance with fresh copies of its internal SOP and
    value nodes, restoring boundary wires and literals. The returned mapping
    is [(inner_id, new_id)]; [displayed] is the parent display afterward. *)
val ungroup :
  instance_id:int ->
  displayed:int option ->
  definition:Network.definition ->
  Network.t ->
  (Network.t * (int * int) list * int option, Flow.Diagnostic.t) result
