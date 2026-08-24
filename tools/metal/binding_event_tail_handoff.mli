type package=Listener_constructor|Listener_queue|Shared_handle|Handle_label|Device_identity|Notification|Type_metadata
type item={id:string;package:package;operation:string;tests:string list}
val callable_ids:string list
val classify:kind:string->string->item
val validate:item list->unit
