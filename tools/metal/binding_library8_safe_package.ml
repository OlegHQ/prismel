let ids =
  [ "class:MTLAttribute"
  ; "class:MTLFunctionReflection"
  ; "class:MTLVertexAttribute"
  ; "typedef:MTLAutoreleasedArgument"
  ; "typedef:MTLAutoreleasedComputePipelineReflection"
  ; "typedef:MTLAutoreleasedRenderPipelineReflection"
  ; "typedef:MTLNewComputePipelineStateWithReflectionCompletionHandler"
  ; "typedef:MTLNewRenderPipelineStateWithReflectionCompletionHandler" ]

let validate () =
  if List.length ids <> 8 || List.length (List.sort_uniq String.compare ids) <> 8
  then invalid_arg "Library8 exact closure drift"
