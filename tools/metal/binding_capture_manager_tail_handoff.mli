type lane=Mechanical|Ownership|Metadata
type package=Destination|Descriptor_graph|Scope_graph|Capture_lifecycle|Type_metadata
type item={id:string;lane:lane;package:package;operation:string;tests:string list}
val mechanical_ids:string list
val classify:kind:string->string->item
val validate:item list->unit
