type public_module =
  | Render_pass_descriptor
  | Layer
  | Drawable
  | Command_buffer

type item =
  { id : string
  ; public_module : public_module
  ; public_operation : string
  ; required_tests : string list
  }

val pending_items : item list
val items_for : public_module -> item list
val modules : public_module list
val private_metadata_ids : string list
val promotable_ids : string list
val prebound_overlap_ids : string list
val validate : unit -> unit
