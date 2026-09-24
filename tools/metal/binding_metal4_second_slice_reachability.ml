let command_buffer_ids =
  [ "method:-[MTL4CommandBuffer popDebugGroup]"; "method:-[MTL4CommandBuffer pushDebugGroup:]"
  ; "method:-[MTL4CommandBuffer resolveCounterHeap:withRange:intoBuffer:waitFence:updateFence:]"
  ; "method:-[MTL4CommandBuffer useResidencySet:]"; "method:-[MTL4CommandBuffer useResidencySets:count:]"
  ; "method:-[MTL4CommandBuffer writeTimestampIntoHeap:atIndex:]" ]
let property owner name setter = ["property:"^owner^":"^name;"method:-["^owner^" "^name^"]";"method:-["^owner^" "^setter^":]"]
let binary_ids =
  [ "method:-[MTL4RenderPipelineBinaryFunctionsDescriptor reset]"
  ; "method:-[MTL4BinaryFunction functionType]"; "property:MTL4BinaryFunction:functionType"
  ; "method:-[MTL4BinaryFunction name]"; "property:MTL4BinaryFunction:name" ] @
  List.concat [ property "MTL4RenderPipelineBinaryFunctionsDescriptor" "vertexAdditionalBinaryFunctions" "setVertexAdditionalBinaryFunctions"; property "MTL4RenderPipelineBinaryFunctionsDescriptor" "fragmentAdditionalBinaryFunctions" "setFragmentAdditionalBinaryFunctions"; property "MTL4RenderPipelineBinaryFunctionsDescriptor" "tileAdditionalBinaryFunctions" "setTileAdditionalBinaryFunctions"; property "MTL4RenderPipelineBinaryFunctionsDescriptor" "objectAdditionalBinaryFunctions" "setObjectAdditionalBinaryFunctions"; property "MTL4RenderPipelineBinaryFunctionsDescriptor" "meshAdditionalBinaryFunctions" "setMeshAdditionalBinaryFunctions" ]
let render_ids =
  [ "method:-[MTL4RenderCommandEncoder drawPrimitives:vertexStart:vertexCount:instanceCount:]"
  ; "method:-[MTL4RenderCommandEncoder drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferLength:instanceCount:]"
  ; "method:-[MTL4RenderCommandEncoder drawMeshThreads:threadsPerObjectThreadgroup:threadsPerMeshThreadgroup:]"
  ; "method:-[MTL4RenderCommandEncoder drawMeshThreadgroupsWithIndirectBuffer:threadsPerObjectThreadgroup:threadsPerMeshThreadgroup:]"
  ; "method:-[MTL4RenderCommandEncoder executeCommandsInBuffer:withRange:]"
  ; "method:-[MTL4RenderCommandEncoder executeCommandsInBuffer:indirectBuffer:]"
  ; "method:-[MTL4RenderCommandEncoder setObjectThreadgroupMemoryLength:atIndex:]"
  ; "method:-[MTL4RenderCommandEncoder setThreadgroupMemoryLength:offset:atIndex:]"
  ; "method:-[MTL4RenderCommandEncoder writeTimestampWithGranularity:afterStage:intoHeap:atIndex:]" ]
let promotable_ids=List.sort_uniq String.compare(command_buffer_ids@binary_ids@render_ids)
let blocked_compute_ids=["method:-[MTL4ComputeCommandEncoder copyFromTensor:sourceOrigin:sourceDimensions:toTensor:destinationOrigin:destinationDimensions:]";"method:-[MTL4ComputeCommandEncoder buildAccelerationStructure:descriptor:scratchBuffer:]";"method:-[MTL4ComputeCommandEncoder refitAccelerationStructure:descriptor:destination:scratchBuffer:]";"method:-[MTL4ComputeCommandEncoder refitAccelerationStructure:descriptor:destination:scratchBuffer:options:]";"method:-[MTL4ComputeCommandEncoder writeCompactedAccelerationStructureSize:toBuffer:]"]
let validate()=if List.length command_buffer_ids<>6||List.length binary_ids<>20||List.length render_ids<>9||List.length promotable_ids<>35||List.length blocked_compute_ids<>5 then failwith"Metal4 second slice reachability drift"
let ()=validate()
