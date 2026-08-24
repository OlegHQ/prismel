let callable_ids =
  [ "method:-[MTL4MachineLearningPipelineState label]"
  ; "property:MTL4MachineLearningPipelineState:label" ]

let metadata_ids =
  [ "class:MTL4MachineLearningPipelineDescriptor"
  ; "class:MTL4MachineLearningPipelineReflection"
  ; "protocol:MTL4MachineLearningPipelineState" ]

let () =
  let ids = callable_ids @ metadata_ids in
  if List.length callable_ids <> 2 || List.length metadata_ids <> 3
     || List.length (List.sort_uniq String.compare ids) <> 5
  then invalid_arg "MTL4MLPipeline5 native closure drift"
