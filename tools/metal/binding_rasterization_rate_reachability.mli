type work_package = Mechanical_native | Handwritten_safe_native | Public_metadata
val mechanical_ids : string list
val descriptor_constructors : string list
val array_access : string list
val layer_storage : string list
val map_ownership : string list
val descriptor_graph : string list
val ownership_ids : string list
val metadata_ids : string list
val all_ids : string list
val package : string -> work_package
val validate : unit -> unit
