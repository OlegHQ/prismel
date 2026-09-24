let existing_ids =
  [ "method:-[MTLAttribute attributeIndex]"; "method:-[MTLAttribute attributeType]"
  ; "method:-[MTLAttribute isActive]"; "method:-[MTLAttribute isPatchControlPointData]"
  ; "method:-[MTLAttribute isPatchData]"; "method:-[MTLAttribute name]"
  ; "property:MTLAttribute:active"; "property:MTLAttribute:attributeIndex"
  ; "property:MTLAttribute:attributeType"; "property:MTLAttribute:name"
  ; "property:MTLAttribute:patchControlPointData"; "property:MTLAttribute:patchData"
  ; "method:-[MTLFunction newArgumentEncoderWithBufferIndex:]"
  ; "method:-[MTLFunction stageInputAttributes]"; "method:-[MTLFunction vertexAttributes]"
  ; "property:MTLFunction:stageInputAttributes"; "property:MTLFunction:vertexAttributes"
  ; "method:-[MTLLibrary newFunctionWithDescriptor:error:]" ]

let remaining_ids =
  [ "method:-[MTLCompileOptions preprocessorMacros]"; "method:-[MTLCompileOptions requiredThreadsPerThreadgroup]"
  ; "method:-[MTLCompileOptions setPreprocessorMacros:]"; "method:-[MTLCompileOptions setRequiredThreadsPerThreadgroup:]"
  ; "property:MTLCompileOptions:preprocessorMacros"; "property:MTLCompileOptions:requiredThreadsPerThreadgroup"
  ; "method:-[MTLFunction newArgumentEncoderWithBufferIndex:reflection:]"
  ; "method:-[MTLFunctionReflection bindings]"; "method:-[MTLFunctionReflection userAnnotation]"
  ; "property:MTLFunctionReflection:bindings"; "property:MTLFunctionReflection:userAnnotation"
  ; "method:-[MTLLibrary newFunctionWithDescriptor:completionHandler:]"
  ; "method:-[MTLLibrary newFunctionWithName:constantValues:completionHandler:]"
  ; "method:-[MTLLibrary newIntersectionFunctionWithDescriptor:completionHandler:]"
  ; "method:-[MTLLibrary newIntersectionFunctionWithDescriptor:error:]"
  ; "method:-[MTLLibrary reflectionForFunctionWithName:]"
  ; "class:MTLAttribute"; "class:MTLFunctionReflection"; "class:MTLVertexAttribute"
  ; "typedef:MTLAutoreleasedArgument"; "typedef:MTLAutoreleasedComputePipelineReflection"
  ; "typedef:MTLAutoreleasedRenderPipelineReflection"
  ; "typedef:MTLNewComputePipelineStateWithReflectionCompletionHandler"
  ; "typedef:MTLNewRenderPipelineStateWithReflectionCompletionHandler" ]

let validate manifest_ids =
  let union = List.sort_uniq String.compare (existing_ids @ remaining_ids) in
  if List.length existing_ids <> 18 || List.length remaining_ids <> 24
     || List.length union <> 42 || union <> List.sort String.compare manifest_ids
  then failwith "MTLLibrary42 native closure drift"
