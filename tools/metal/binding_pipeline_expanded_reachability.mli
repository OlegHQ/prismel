type status=Promotable|Blocked
val ownership_ids:string list
val mechanical_ids:string list
val pending_family_ids:string list
val enabling_device_ids:string list
val promotable_ids:string list
val status:string->status
val validate:unit->unit
