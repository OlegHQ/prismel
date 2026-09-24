type lane=Mechanical_value|Handwritten_lifecycle
type item={id:string;lane:lane}
val items:item list
val count:lane->int
