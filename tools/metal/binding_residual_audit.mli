type lane=Mechanical_value|Handwritten_ownership
type item={id:string;lane:lane}
val items:item list
val count:lane->int
val routed_active_counts:(string*int)list
