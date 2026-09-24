let property owner name setter =
  [ "property:"^owner^":"^name; "method:-["^owner^" "^name^"]"; "method:-["^owner^" "^setter^":]" ]
let promotable_ids =
  [ property "MTLPipelineBufferDescriptor" "mutability" "setMutability"
  ; property "MTLRenderPipelineColorAttachmentDescriptor" "pixelFormat" "setPixelFormat"
  ; property "MTLRenderPipelineColorAttachmentDescriptor" "sourceRGBBlendFactor" "setSourceRGBBlendFactor"
  ; property "MTLRenderPipelineColorAttachmentDescriptor" "destinationRGBBlendFactor" "setDestinationRGBBlendFactor"
  ; property "MTLRenderPipelineColorAttachmentDescriptor" "rgbBlendOperation" "setRgbBlendOperation"
  ; property "MTLRenderPipelineColorAttachmentDescriptor" "sourceAlphaBlendFactor" "setSourceAlphaBlendFactor"
  ; property "MTLRenderPipelineColorAttachmentDescriptor" "destinationAlphaBlendFactor" "setDestinationAlphaBlendFactor"
  ; property "MTLRenderPipelineColorAttachmentDescriptor" "alphaBlendOperation" "setAlphaBlendOperation"
  ; property "MTLRenderPipelineColorAttachmentDescriptor" "writeMask" "setWriteMask"
  ; property "MTLMeshRenderPipelineDescriptor" "label" "setLabel"
  ; property "MTLMeshRenderPipelineDescriptor" "depthAttachmentPixelFormat" "setDepthAttachmentPixelFormat"
  ; property "MTLMeshRenderPipelineDescriptor" "stencilAttachmentPixelFormat" "setStencilAttachmentPixelFormat"
  ; property "MTLMeshRenderPipelineDescriptor" "requiredThreadsPerMeshThreadgroup" "setRequiredThreadsPerMeshThreadgroup"
  ; property "MTLMeshRenderPipelineDescriptor" "requiredThreadsPerObjectThreadgroup" "setRequiredThreadsPerObjectThreadgroup"
  ; property "MTLTileRenderPipelineDescriptor" "label" "setLabel"
  ; property "MTLTileRenderPipelineDescriptor" "requiredThreadsPerThreadgroup" "setRequiredThreadsPerThreadgroup"
  ] |> List.concat |> List.sort_uniq String.compare
let validate()=if List.length promotable_ids<>48 then failwith"Mesh/tile105 safe closure drift"
let ()=validate()
