type lane=Ownership|Metadata
type package=Geometry_descriptor|Instance_descriptor|Primitive_descriptor|Motion_data|Class_metadata|Instance_value
type item={id:string;lane:lane;package:package;operation:string;tests:string list}
val classify:kind:string->string->item
val validate:item list->unit
