let ids =
  [ "method:-[MTL4Compiler newMachineLearningPipelineStateWithDescriptor:completionHandler:]"
  ; "typedef:MTL4NewMachineLearningPipelineStateCompletionHandler" ]

let validate () =
  if List.length ids <> 2 || List.length (List.sort_uniq String.compare ids) <> 2
  then invalid_arg "MTL4Compiler async ML exact2 drift"
