type lane=Mechanical|Ownership|Metadata
type package=Layout_scalar|Identity_label|Argument_storage|Single_binding|Array_binding|Type_metadata
type item={id:string;lane:lane;package:package;operation:string;tests:string list}
val mechanical_ids:string list
val classify:kind:string->string->item
val validate:item list->unit
