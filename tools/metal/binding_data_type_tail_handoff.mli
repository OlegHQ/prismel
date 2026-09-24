type package=Opaque_resource_type|Packed_value_type
type item={id:string;package:package;public_value:string;tests:string list}
val expected_ids:string list
val classify:string->item
val validate:item list->unit
