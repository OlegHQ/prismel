let promotion_ids =
  [ "method:-[MTLRenderCommandEncoder drawPrimitives:vertexStart:vertexCount:instanceCount:]"
  ; "method:-[MTLRenderCommandEncoder setBlendColorRed:green:blue:alpha:]"
  ; "method:-[MTLRenderCommandEncoder setCullMode:]"
  ; "method:-[MTLRenderCommandEncoder setDepthBias:slopeScale:clamp:]"
  ; "method:-[MTLRenderCommandEncoder setFragmentBuffer:offset:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setFragmentTexture:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setFrontFacingWinding:]"
  ; "method:-[MTLRenderCommandEncoder setRenderPipelineState:]"
  ; "method:-[MTLRenderCommandEncoder setScissorRect:]"
  ; "method:-[MTLRenderCommandEncoder setStencilFrontReferenceValue:backReferenceValue:]"
  ; "method:-[MTLRenderCommandEncoder setTriangleFillMode:]"
  ; "method:-[MTLRenderCommandEncoder setVertexBuffer:offset:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setVertexTexture:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setViewport:]"
  ; "method:-[MTLRenderCommandEncoder setVisibilityResultMode:offset:]"
  ; "method:-[MTLRenderCommandEncoder tileHeight]"
  ; "method:-[MTLRenderCommandEncoder tileWidth]"
  ; "property:MTLRenderCommandEncoder:tileHeight"
  ; "property:MTLRenderCommandEncoder:tileWidth"
  ]

let expected_count = 19

let () =
  if List.length promotion_ids <> expected_count
     || List.length (List.sort_uniq String.compare promotion_ids) <> expected_count then
    invalid_arg "classic render encoder promotion evidence drift"

let is_bound_identifier identifier = List.mem identifier promotion_ids
