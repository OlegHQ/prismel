let promotable_ids =
  [ "method:-[MTLComputePipelineDescriptor buffers]"
  ; "method:-[MTLComputePipelineDescriptor insertLibraries]"
  ; "method:-[MTLComputePipelineDescriptor setInsertLibraries:]"
  ; "method:-[MTLComputePipelineReflection arguments]"
  ; "method:-[MTLComputePipelineState functionHandleWithName:]"
  ; "method:-[MTLComputePipelineState newComputePipelineStateWithAdditionalBinaryFunctions:error:]"
  ; "method:-[MTLComputePipelineState newComputePipelineStateWithBinaryFunctions:error:]"
  ; "property:MTLComputePipelineDescriptor:buffers"
  ; "property:MTLComputePipelineDescriptor:insertLibraries"
  ; "property:MTLComputePipelineReflection:arguments" ]

let blocked_ids =
  [ "method:-[MTLComputePipelineState functionHandleWithBinaryFunction:]" ]

let () =
  if List.length promotable_ids<>10||List.length blocked_ids<>1 then
    invalid_arg"ComputePipeline11 safe closure drift"
