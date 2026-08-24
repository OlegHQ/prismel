type package = Constructors | Layer_graph | Descriptor_graph | Rate_map
type item = { id:string; package:package; operation:string; tests:string list }
val callable_ids:string list
val items:item list
val items_for:package->item list
val m1_capability_tests:string list
val validate:unit->unit
