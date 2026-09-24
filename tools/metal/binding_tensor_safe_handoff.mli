type public_module = Extents | Descriptor | Tensor | Byte_slice
type item = { id:string; public_module:public_module; operation:string; tests:string list }
val mechanical_ids:string list
val ownership_ids:string list
val callable_ids:string list
val safe41_ids:string list
val safe47_ids:string list
val device_enablers:string list
val buffer_enabler:string
val items:item list
val items_for:public_module->item list
val validate:unit->unit
