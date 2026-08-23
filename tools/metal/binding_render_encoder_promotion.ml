let promotion_ids =
  [ "method:-[MTLRenderCommandEncoder drawPrimitives:vertexStart:vertexCount:instanceCount:]"
  ; "method:-[MTLRenderCommandEncoder setBlendColorRed:green:blue:alpha:]"
  ; "method:-[MTLRenderCommandEncoder setColorStoreAction:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setColorStoreActionOptions:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setCullMode:]"
  ; "method:-[MTLRenderCommandEncoder setDepthBias:slopeScale:clamp:]"
  ; "method:-[MTLRenderCommandEncoder setFragmentBuffer:offset:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setFragmentBytes:length:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setFragmentSamplerState:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setFragmentSamplerState:lodMinClamp:lodMaxClamp:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setFragmentTexture:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setFrontFacingWinding:]"
  ; "method:-[MTLRenderCommandEncoder setRenderPipelineState:]"
  ; "method:-[MTLRenderCommandEncoder setScissorRect:]"
  ; "method:-[MTLRenderCommandEncoder setStencilFrontReferenceValue:backReferenceValue:]"
  ; "method:-[MTLRenderCommandEncoder setTriangleFillMode:]"
  ; "method:-[MTLRenderCommandEncoder setVertexBuffer:offset:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setVertexBytes:length:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setVertexSamplerState:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setVertexSamplerState:lodMinClamp:lodMaxClamp:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setVertexTexture:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setViewport:]"
  ; "method:-[MTLRenderCommandEncoder setVisibilityResultMode:offset:]"
  ; "method:-[MTLRenderCommandEncoder tileHeight]"
  ; "method:-[MTLRenderCommandEncoder tileWidth]"
  ; "property:MTLRenderCommandEncoder:tileHeight"
  ; "property:MTLRenderCommandEncoder:tileWidth"
  ] @ List.map (fun (entry : Binding_render_encoder_resource_plan.entry) -> entry.id)
      Binding_render_encoder_resource_plan.entries

let expected_count = 46

let () =
  if List.length promotion_ids <> expected_count
     || List.length (List.sort_uniq String.compare promotion_ids) <> expected_count then
    invalid_arg "classic render encoder promotion evidence drift"

let is_bound_identifier identifier = List.mem identifier promotion_ids
