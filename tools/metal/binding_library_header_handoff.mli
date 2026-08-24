type lane=Mechanical|Ownership|Metadata
type package=Attribute|Compile_options|Function|Reflection|Library|Type_metadata
type item={id:string;lane:lane;package:package;operation:string;tests:string list}
val mechanical_ids:string list
val classify:kind:string->string->item
val validate:item list->unit
