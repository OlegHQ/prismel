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
