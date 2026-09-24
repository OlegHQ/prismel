type lane = Mechanical | Ownership | Metadata
type package = Options | Input_node | Function_node | Graph | Stitched_descriptor | Type_metadata
type item = { id:string; lane:lane; package:package; operation:string; tests:string list }
val mechanical_ids:string list
val callable_ids:string list
val safe24_ids:string list
val classify:kind:string->string->item
val validate:item list->unit
