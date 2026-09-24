open Binding_mesh_tile_pipeline_spec

let expected_real_pipeline_owners =
  [ "MTLMeshRenderPipelineDescriptor"; "MTLTileRenderPipelineDescriptor" ]

let required_handwritten_invariants =
  [ "same-device function/archive/dynamic-library validation"
  ; "function stage validation"
  ; "borrowed inputs retained through pipeline creation"
  ; "linked-function uniqueness and stage ownership"
  ; "color attachment count and pixel-format capability"
  ; "pipeline buffer mutability index bounds"
  ; "nullable object and copied-label ownership"
  ; "reset and indexed-subscript exact behavior"
  ; "completion-owned reflection and NSError lifetime"
  ]

let fail format =
  Printf.ksprintf
    (fun message -> invalid_arg ("Metal mesh/tile pipeline evidence: " ^ message))
    format

let validate selection =
  if List.length selection.Binding_mesh_tile_pipeline_plan.declarations <> 105
  then fail "production batch is not closed over 105 declarations";
  List.iter
    (fun declaration ->
      if declaration.classification <> "unreviewed" then
        fail "foundation declaration was promoted without conformance: %s"
          declaration.id;
      if
        declaration.header <> "Metal/MTLRenderPipeline.h"
        && declaration.header <> "Metal/MTLPipeline.h"
      then
        fail "unexpected header for %s" declaration.id;
      if declaration.macos_introduced = None then
        fail "missing exact availability for %s" declaration.id)
    selection.declarations;
  List.iter
    (fun declaration ->
      match property_kind declaration with
      | Borrowed_function _ | Borrowed_binary_archives
      | Borrowed_dynamic_libraries | Linked_functions | Buffer_descriptors
      | Color_attachments -> ()
      | _ -> fail "handwritten ownership assigned to value property %s" declaration.id)
    selection.handwritten_properties;
  if List.length required_handwritten_invariants <> 9 then
    fail "handwritten invariant closure drift"
