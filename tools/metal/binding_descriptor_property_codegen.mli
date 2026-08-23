val render_public_record_types : Binding_descriptor_property_spec.entry list -> string
val render_public_ml : Binding_descriptor_property_spec.entry list -> string
val render_public_mli : Binding_descriptor_property_spec.entry list -> string
val render_public_tests : Binding_descriptor_property_spec.entry list -> string
val render_native_materializers : Binding_descriptor_property_spec.entry list -> string
val render_native_roundtrip_tests : Binding_descriptor_property_spec.entry list -> string
val render_native_conformance_executable :
  Binding_descriptor_property_spec.entry list -> string
