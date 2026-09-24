type handoff=Existing_safe|Constructor_graph|Parent_metadata|Completion_retention|Buffer_backed_texture_graph
type item={id:string;raw_symbol:string;native_symbol:string;safe_operation:string;handoff:handoff}
val items:item list
val buffer_backed_texture_ids:string list
val validate:unit->unit
