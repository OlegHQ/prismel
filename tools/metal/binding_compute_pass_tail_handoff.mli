type lane=Mechanical|Ownership|Metadata
type package=Dispatch|Sample_indices|Pass_graph|Sample_buffer|Attachment_array|Type_metadata
type item={id:string;lane:lane;package:package;operation:string;tests:string list}
val mechanical_ids:string list
val callable_ids:string list
val classify:kind:string->string->item
val validate:item list->unit
