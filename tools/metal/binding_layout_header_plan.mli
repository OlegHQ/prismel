type declaration={id:string;kind:string;owner:string option;name:string;signature:string}
type lane=Metadata|Mechanical|Handwritten_ownership
type entry={declaration:declaration;lane:lane}
val headers:string list val expected_count:int val expected_digest:string
val select:declaration list->entry list val count:lane->entry list->int val validate:entry list->unit
