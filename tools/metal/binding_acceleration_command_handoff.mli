type lane=Mechanical|Ownership|Metadata
type package=Encoder|Pass_descriptor|Sample_attachment|Attachment_array|Type_metadata
type item={id:string;lane:lane;package:package;operation:string;tests:string list}
val mechanical_ids:string list
val classify:kind:string->string->item
val validate:item list->unit
