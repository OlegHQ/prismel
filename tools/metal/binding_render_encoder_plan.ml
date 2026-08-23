let owner = "MTLRenderCommandEncoder"
let expected_method_count = 131
let expected_property_count = 2
let expected_declaration_count = 133

(* SHA-256 of sorted TSV rows: id, kind, exact SDK signature, canonical macOS
   introduction and sorted Clang attributes. This freezes the complete owner
   closure without duplicating 133 long selectors in handwritten source. *)
let expected_signature_digest =
  "1acf1024ee348e211bff0dbfb0a98583fde97456fcbb2c60023ef06c2212529c"

let source_paths =
  [ "tools/metal/binding_render_encoder_plan.ml"
  ; "tools/metal/binding_render_encoder_plan.mli"
  ; "tools/metal/binding_render_encoder_evidence.ml"
  ; "tools/metal/binding_render_encoder_evidence.mli"
  ; "tools/metal/binding_render_encoder_codegen.ml"
  ; "tools/metal/binding_render_encoder_codegen.mli"
  ; "tools/metal/binding_render_encoder_model.ml"
  ; "tools/metal/binding_render_encoder_model.mli"
  ]

let () =
  if expected_method_count + expected_property_count
     <> expected_declaration_count
  then invalid_arg "render encoder declaration relationship drift"
