type package=Copy|Fill_mipmap|Access_counter|Optimize|Indirect_reset|Counter_sample|Synchronize|Fence
type item={id:string;package:package;operation:string;tests:string list}
val callable_ids:string list
val classify:string->item
val validate:item list->unit
