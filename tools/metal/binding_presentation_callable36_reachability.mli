type handoff=Scalar_snapshot|Sample_positions|Nullable_rasterization_graph|Layer_identity|Drawable_parent|Command_lifecycle|Attachment_graph|Descriptor_encoder
type item={id:string;raw_symbols:string list;native_symbols:string list;safe_operation:string;handoff:handoff}
val render_pass_ids:string list
val layer_drawable_ids:string list
val items:item list
val callable_ids:string list
val blocked_ids:string list
val private_metadata_ids:string list
val validate:unit->unit
