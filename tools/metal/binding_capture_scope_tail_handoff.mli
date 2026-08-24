type package=Lifecycle|Queue_identity|Device_identity|Label|Type_metadata
type item={id:string;package:package;operation:string;tests:string list}
val callable_ids:string list
val classify:kind:string->string->item
val validate:item list->unit
