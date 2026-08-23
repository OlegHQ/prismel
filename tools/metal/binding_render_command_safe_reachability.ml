type status = Promotable | Blocked of string
type item =
  { id : string
  ; public_operation : string
  ; required_test : string
  ; status : status
  }

let initially_promotable_ids =
  [ "method:-[MTLRenderCommandEncoder drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:]"
  ; "method:-[MTLRenderCommandEncoder drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:]"
  ; "method:-[MTLRenderCommandEncoder drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:baseVertex:baseInstance:]"
  ; "method:-[MTLRenderCommandEncoder drawIndexedPrimitives:indexType:indexBuffer:indexBufferOffset:indirectBuffer:indirectBufferOffset:]"
  ; "method:-[MTLRenderCommandEncoder drawPatches:patchIndexBuffer:patchIndexBufferOffset:indirectBuffer:indirectBufferOffset:]"
  ; "method:-[MTLRenderCommandEncoder drawPatches:patchStart:patchCount:patchIndexBuffer:patchIndexBufferOffset:instanceCount:baseInstance:]"
  ; "method:-[MTLRenderCommandEncoder drawPrimitives:indirectBuffer:indirectBufferOffset:]"
  ; "method:-[MTLRenderCommandEncoder setDepthClipMode:]"
  ; "method:-[MTLRenderCommandEncoder setDepthStencilState:]"
  ; "method:-[MTLRenderCommandEncoder setDepthTestMinBound:maxBound:]"
  ; "method:-[MTLRenderCommandEncoder setFragmentTextures:withRange:]"
  ; "method:-[MTLRenderCommandEncoder setMeshBuffer:offset:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setMeshBytes:length:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setMeshSamplerState:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setMeshSamplerState:lodMinClamp:lodMaxClamp:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setMeshTexture:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setMeshTextures:withRange:]"
  ; "method:-[MTLRenderCommandEncoder setObjectBuffer:offset:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setObjectBytes:length:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setObjectSamplerState:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setObjectSamplerState:lodMinClamp:lodMaxClamp:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setObjectTexture:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setObjectTextures:withRange:]"
  ; "method:-[MTLRenderCommandEncoder setScissorRects:count:]"
  ; "method:-[MTLRenderCommandEncoder setStencilReferenceValue:]"
  ; "method:-[MTLRenderCommandEncoder setTessellationFactorBuffer:offset:instanceStride:]"
  ; "method:-[MTLRenderCommandEncoder setTessellationFactorScale:]"
  ; "method:-[MTLRenderCommandEncoder setTileBuffer:offset:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setTileBytes:length:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setTileSamplerState:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setTileSamplerState:lodMinClamp:lodMaxClamp:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setTileTexture:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setTileTextures:withRange:]"
  ; "method:-[MTLRenderCommandEncoder setVertexAmplificationCount:viewMappings:]"
  ; "method:-[MTLRenderCommandEncoder setVertexBuffer:offset:attributeStride:atIndex:]"
  ; "method:-[MTLRenderCommandEncoder setVertexTextures:withRange:]"
  ; "method:-[MTLRenderCommandEncoder setViewports:count:]"
  ] |> List.sort String.compare

let native_verified_ids =
  [ "method:-[MTLRenderCommandEncoder setFragmentAccelerationStructure:atBufferIndex:]"
  ; "method:-[MTLRenderCommandEncoder setFragmentIntersectionFunctionTable:atBufferIndex:]"
  ; "method:-[MTLRenderCommandEncoder setFragmentIntersectionFunctionTables:withBufferRange:]"
  ; "method:-[MTLRenderCommandEncoder setFragmentSamplerStates:withRange:]"
  ; "method:-[MTLRenderCommandEncoder setFragmentVisibleFunctionTable:atBufferIndex:]"
  ; "method:-[MTLRenderCommandEncoder setFragmentVisibleFunctionTables:withBufferRange:]"
  ; "method:-[MTLRenderCommandEncoder setMeshSamplerStates:withRange:]"
  ; "method:-[MTLRenderCommandEncoder setObjectSamplerStates:withRange:]"
  ; "method:-[MTLRenderCommandEncoder setTileAccelerationStructure:atBufferIndex:]"
  ; "method:-[MTLRenderCommandEncoder setTileIntersectionFunctionTable:atBufferIndex:]"
  ; "method:-[MTLRenderCommandEncoder setTileIntersectionFunctionTables:withBufferRange:]"
  ; "method:-[MTLRenderCommandEncoder setTileSamplerStates:withRange:]"
  ; "method:-[MTLRenderCommandEncoder setTileVisibleFunctionTable:atBufferIndex:]"
  ; "method:-[MTLRenderCommandEncoder setTileVisibleFunctionTables:withBufferRange:]"
  ; "method:-[MTLRenderCommandEncoder setVertexAccelerationStructure:atBufferIndex:]"
  ; "method:-[MTLRenderCommandEncoder setVertexIntersectionFunctionTable:atBufferIndex:]"
  ; "method:-[MTLRenderCommandEncoder setVertexIntersectionFunctionTables:withBufferRange:]"
  ; "method:-[MTLRenderCommandEncoder setVertexSamplerStates:withRange:]"
  ; "method:-[MTLRenderCommandEncoder setVertexVisibleFunctionTable:atBufferIndex:]"
  ; "method:-[MTLRenderCommandEncoder setVertexVisibleFunctionTables:withBufferRange:]"
  ] |> List.sort String.compare

let promotable_ids =
  List.sort_uniq String.compare (initially_promotable_ids @ native_verified_ids)

let contains text needle =
  let n = String.length needle in
  let rec loop i = i + n <= String.length text
    && (String.sub text i n = needle || loop (i + 1))
  in loop 0

let public_operation id =
  if contains id "drawIndexedPrimitives" then "Metal.Render_encoder.draw_indexed*"
  else if contains id "drawPatches" then "Metal.Render_encoder.draw_patches*"
  else if contains id "drawPrimitives:indirectBuffer" then "Metal.Render_encoder.draw_indirect"
  else if contains id "setDepthStencilState" then "Metal.Render_encoder.set_depth_stencil_state"
  else if contains id "setDepthClipMode" then "Metal.Render_encoder.set_depth_clip_mode"
  else if contains id "setDepthTestMinBound" then "Metal.Render_encoder.set_depth_bounds"
  else if contains id "setViewports" then "Metal.Render_encoder.set_viewports"
  else if contains id "setScissorRects" then "Metal.Render_encoder.set_scissors"
  else if contains id "setVertexAmplificationCount" then "Metal.Render_encoder.set_vertex_amplification"
  else if contains id "setTessellationFactorBuffer" then "Metal.Render_encoder.set_tessellation_factor_buffer"
  else if contains id "setTessellationFactorScale" then "Metal.Render_encoder.set_tessellation_factor_scale"
  else if contains id "setStencilReferenceValue" then "Metal.Render_encoder.set_stencil_reference_value"
  else if contains id "AccelerationStructure" then "Metal.Render_encoder.set_stage_acceleration_structure"
  else if contains id "VisibleFunctionTable" then "Metal.Render_encoder.set_stage_visible_function_table(s)"
  else if contains id "IntersectionFunctionTable" then "Metal.Render_encoder.set_stage_intersection_function_table(s)"
  else if contains id "Buffer:" || contains id "Bytes:" || contains id "Texture"
       || contains id "SamplerState" then "Metal.Render_encoder.set_stage_*"
  else "missing public Render_encoder operation"

let required_test id =
  if contains id "draw" then
    "range/alignment/index-type rejection, completion retention, exact M1 pixels"
  else if contains id "Buffer" || contains id "Texture" || contains id "Sampler" then
    "destroyed/wrong-device rejection, index/cardinality checks, completion retention"
  else if contains id "SampleBufferAttachment" then
    "owned constructor, getter/setter round trip, parent lifetime, zero handle delta"
  else "finite/range rejection, selector exactness, zero handle delta"

let item id =
  let promotable = List.mem id promotable_ids in
  { id; public_operation = public_operation id; required_test = required_test id
  ; status =
      if promotable then Promotable
      else Blocked "no committed safe public/test closure" }

let items = List.map item Binding_render_encoder_manifest.ids
let blocked =
  List.filter
    (fun item -> match item.status with Blocked _ -> true | Promotable -> false)
    items

let validate () =
  if List.length items <> 102 then failwith "Render-command102 audit count drift";
  let manifest = List.sort String.compare Binding_render_encoder_manifest.ids in
  let ids = List.map (fun item -> item.id) items |> List.sort String.compare in
  if ids <> manifest || List.sort_uniq String.compare ids <> ids then
    failwith "Render-command102 audit does not close exact unique manifest";
  if List.exists (fun id -> not (List.mem id manifest)) promotable_ids then
    failwith "Render-command102 promotable ID escaped manifest";
  if List.length promotable_ids <> 57 || List.length blocked <> 45
  then
    failwith "Render-command102 safe/gap cardinality drift"

let () = validate ()
