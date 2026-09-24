type lane=Mechanical_value|Ownership
type package=Stage_values|Barrier|Device_identity|Label|Debug_group
type item={id:string;lane:lane;package:package;operation:string;tests:string list}
val classify:kind:string->string->item
val validate:item list->unit
