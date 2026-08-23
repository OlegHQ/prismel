type selection =
  { declarations : Binding_mesh_tile_pipeline_spec.declaration list
  ; classes : Binding_mesh_tile_pipeline_spec.declaration list
  ; methods : Binding_mesh_tile_pipeline_spec.declaration list
  ; properties : Binding_mesh_tile_pipeline_spec.declaration list
  ; mechanical_properties : Binding_mesh_tile_pipeline_spec.declaration list
  ; handwritten_properties : Binding_mesh_tile_pipeline_spec.declaration list
  ; owners : string list
  }

val expected_declaration_count : int
val expected_class_count : int
val expected_method_count : int
val expected_property_count : int
val expected_mechanical_property_count : int
val expected_handwritten_property_count : int
val expected_identifier_sha256 : string
val select : Binding_mesh_tile_pipeline_spec.declaration list -> selection
val source_paths : string list
