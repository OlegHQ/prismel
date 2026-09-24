let entries = Binding_render_pipeline_scalar_plan.entries
let render_public_ml () = Binding_descriptor_property_codegen.render_public_ml entries
let render_public_mli () = Binding_descriptor_property_codegen.render_public_mli entries
let render_public_tests () = Binding_descriptor_property_codegen.render_public_tests entries
let render_native_materializers () =
  Binding_descriptor_property_codegen.render_native_materializers entries
let render_native_conformance () =
  Binding_descriptor_property_codegen.render_native_conformance_executable entries
