type package=Sentinel|Pvrtc
type item={id:string;package:package;tests:string list}
val classify:string->item
val validate:item list->unit
