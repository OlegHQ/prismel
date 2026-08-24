let callable_ids =
  [ "method:-[MTLComputeCommandEncoder setAccelerationStructure:atBufferIndex:]"
  ; "method:-[MTLComputeCommandEncoder setBuffer:offset:attributeStride:atIndex:]"
  ; "method:-[MTLComputeCommandEncoder setBufferOffset:atIndex:]"
  ; "method:-[MTLComputeCommandEncoder setBufferOffset:attributeStride:atIndex:]"
  ; "method:-[MTLComputeCommandEncoder setBuffers:offsets:attributeStrides:withRange:]"
  ; "method:-[MTLComputeCommandEncoder setBuffers:offsets:withRange:]"
  ; "method:-[MTLComputeCommandEncoder setBytes:length:attributeStride:atIndex:]"
  ; "method:-[MTLComputeCommandEncoder setIntersectionFunctionTable:atBufferIndex:]"
  ; "method:-[MTLComputeCommandEncoder setIntersectionFunctionTables:withBufferRange:]"
  ; "method:-[MTLComputeCommandEncoder setSamplerState:atIndex:]"
  ; "method:-[MTLComputeCommandEncoder setSamplerState:lodMinClamp:lodMaxClamp:atIndex:]"
  ; "method:-[MTLComputeCommandEncoder setSamplerStates:lodMinClamps:lodMaxClamps:withRange:]"
  ; "method:-[MTLComputeCommandEncoder setSamplerStates:withRange:]"
  ; "method:-[MTLComputeCommandEncoder setTextures:withRange:]"
  ; "method:-[MTLComputeCommandEncoder setVisibleFunctionTable:atBufferIndex:]"
  ; "method:-[MTLComputeCommandEncoder setVisibleFunctionTables:withBufferRange:]" ]
let validate () =
  if List.length callable_ids <> 16 then invalid_arg "ComputeEncoder safe16 drift";
  List.iter (fun id -> if not (List.mem id Binding_compute_encoder35_native_closure.callable_ids) then invalid_arg ("ComputeEncoder safe ID outside native closure: " ^ id)) callable_ids
