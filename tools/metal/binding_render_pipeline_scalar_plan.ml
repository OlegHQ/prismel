open Binding_descriptor_property_spec

let a = [ "AvailabilityAttr" ]

let p ?(attributes = []) ?(default = 0L) ?getter owner name signature introduced =
  entry ~attributes ~default_int64:default ?getter ~owner ~name
    ~header:"Metal/MTLRenderPipeline.h" ~signature ~introduced ()

(* This is the complete non-deprecated, canonical-getter, non-bitmask,
   fixed-scalar property
   family on the three public render-pipeline descriptor kinds and their color
   attachment descriptor in the pinned SDK. Object, string, array, MTLSize and
   MTLColorWriteMask properties deliberately use their separate ownership,
   struct, and flags templates. *)
let entries =
  [ p ~getter:"isAlphaToCoverageEnabled" "MTLMeshRenderPipelineDescriptor" "alphaToCoverageEnabled" "BOOL" "13.0"
  ; p ~getter:"isAlphaToOneEnabled" "MTLMeshRenderPipelineDescriptor" "alphaToOneEnabled" "BOOL" "13.0"
  ; p "MTLMeshRenderPipelineDescriptor" "maxTotalThreadgroupsPerMeshGrid" "NSUInteger" "13.0"
  ; p "MTLMeshRenderPipelineDescriptor" "maxTotalThreadsPerMeshThreadgroup" "NSUInteger" "13.0"
  ; p "MTLMeshRenderPipelineDescriptor" "maxTotalThreadsPerObjectThreadgroup" "NSUInteger" "13.0"
  ; p ~default:1L "MTLMeshRenderPipelineDescriptor" "maxVertexAmplificationCount" "NSUInteger" "13.0"
  ; p "MTLMeshRenderPipelineDescriptor" "meshThreadgroupSizeIsMultipleOfThreadExecutionWidth" "BOOL" "13.0"
  ; p "MTLMeshRenderPipelineDescriptor" "objectThreadgroupSizeIsMultipleOfThreadExecutionWidth" "BOOL" "13.0"
  ; p "MTLMeshRenderPipelineDescriptor" "payloadMemoryLength" "NSUInteger" "13.0"
  ; p ~default:1L "MTLMeshRenderPipelineDescriptor" "rasterSampleCount" "NSUInteger" "13.0"
  ; p ~default:1L ~getter:"isRasterizationEnabled" "MTLMeshRenderPipelineDescriptor" "rasterizationEnabled" "BOOL" "13.0"
  ; p ~attributes:a "MTLMeshRenderPipelineDescriptor" "shaderValidation" "MTLShaderValidation" "15.0"
  ; p ~attributes:a "MTLMeshRenderPipelineDescriptor" "supportIndirectCommandBuffers" "BOOL" "14.0"

  ; p ~getter:"isBlendingEnabled" "MTLRenderPipelineColorAttachmentDescriptor" "blendingEnabled" "BOOL" "10.11"

  ; p ~getter:"isAlphaToCoverageEnabled" "MTLRenderPipelineDescriptor" "alphaToCoverageEnabled" "BOOL" "10.11"
  ; p ~getter:"isAlphaToOneEnabled" "MTLRenderPipelineDescriptor" "alphaToOneEnabled" "BOOL" "10.11"
  ; p ~attributes:a ~default:1L "MTLRenderPipelineDescriptor" "maxFragmentCallStackDepth" "NSUInteger" "12.0"
  ; p ~attributes:a ~default:16L "MTLRenderPipelineDescriptor" "maxTessellationFactor" "NSUInteger" "10.12"
  ; p ~attributes:a ~default:1L "MTLRenderPipelineDescriptor" "maxVertexAmplificationCount" "NSUInteger" "10.15.4"
  ; p ~attributes:a ~default:1L "MTLRenderPipelineDescriptor" "maxVertexCallStackDepth" "NSUInteger" "12.0"
  ; p ~default:1L "MTLRenderPipelineDescriptor" "rasterSampleCount" "NSUInteger" "10.11"
  ; p ~default:1L ~getter:"isRasterizationEnabled" "MTLRenderPipelineDescriptor" "rasterizationEnabled" "BOOL" "10.11"
  ; p ~attributes:a "MTLRenderPipelineDescriptor" "shaderValidation" "MTLShaderValidation" "15.0"
  ; p ~attributes:a "MTLRenderPipelineDescriptor" "supportAddingFragmentBinaryFunctions" "BOOL" "12.0"
  ; p ~attributes:a "MTLRenderPipelineDescriptor" "supportAddingVertexBinaryFunctions" "BOOL" "12.0"
  ; p ~attributes:a "MTLRenderPipelineDescriptor" "supportIndirectCommandBuffers" "BOOL" "10.14"
  ; p ~attributes:a "MTLRenderPipelineDescriptor" "tessellationControlPointIndexType" "MTLTessellationControlPointIndexType" "10.12"
  ; p ~attributes:a "MTLRenderPipelineDescriptor" "tessellationFactorFormat" "MTLTessellationFactorFormat" "10.12"
  ; p ~attributes:a ~getter:"isTessellationFactorScaleEnabled" "MTLRenderPipelineDescriptor" "tessellationFactorScaleEnabled" "BOOL" "10.12"
  ; p ~attributes:a "MTLRenderPipelineDescriptor" "tessellationFactorStepFunction" "MTLTessellationFactorStepFunction" "10.12"
  ; p ~attributes:a "MTLRenderPipelineDescriptor" "tessellationPartitionMode" "MTLTessellationPartitionMode" "10.12"

  ; p ~attributes:a ~default:1L "MTLTileRenderPipelineDescriptor" "maxCallStackDepth" "NSUInteger" "12.0"
  ; p ~attributes:a "MTLTileRenderPipelineDescriptor" "maxTotalThreadsPerThreadgroup" "NSUInteger" "11.0"
  ; p ~default:1L "MTLTileRenderPipelineDescriptor" "rasterSampleCount" "NSUInteger" "11.0"
  ; p ~attributes:a "MTLTileRenderPipelineDescriptor" "shaderValidation" "MTLShaderValidation" "15.0"
  ; p ~attributes:a "MTLTileRenderPipelineDescriptor" "supportAddingBinaryFunctions" "BOOL" "12.0"
  ; p "MTLTileRenderPipelineDescriptor" "threadgroupSizeMatchesTileSize" "BOOL" "11.0"
  ]

let expected_property_count = 37
let expected_inventory_id_count = 111
let expected_owner_count = 4

let source_paths =
  [ "tools/metal/binding_render_pipeline_scalar_plan.ml"
  ; "tools/metal/binding_render_pipeline_scalar_plan.mli"
  ; "tools/metal/binding_render_pipeline_scalar_evidence.ml"
  ; "tools/metal/binding_render_pipeline_scalar_evidence.mli"
  ; "tools/metal/binding_render_pipeline_scalar_codegen.ml"
  ; "tools/metal/binding_render_pipeline_scalar_codegen.mli"
  ]

let () =
  validate entries;
  if List.length entries <> expected_property_count then
    invalid_arg "render-pipeline scalar property count drift";
  let ids = List.concat_map inventory_ids entries in
  if List.length ids <> expected_inventory_id_count then
    invalid_arg "render-pipeline scalar inventory-ID count drift";
  let owners =
    entries |> List.map (fun entry -> entry.owner) |> List.sort_uniq String.compare
  in
  if List.length owners <> expected_owner_count then
    invalid_arg "render-pipeline scalar owner count drift"
