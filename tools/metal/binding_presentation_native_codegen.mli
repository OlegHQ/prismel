type declaration = Binding_presentation_spec.declaration
val generated_ids : string list
val render_native : declaration list -> string
val render_raw_externals : declaration list -> string
val validate : declaration list -> unit
