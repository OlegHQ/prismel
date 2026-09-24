type status=Promotable|Blocked
val ml_ids:string list
val specialized_ids:string list
val stitched_ids:string list
val pending_ids:string list
val promotable_ids:string list
val blocked_stitched_graph_ids:string list
val status:string->status
val validate:unit->unit
