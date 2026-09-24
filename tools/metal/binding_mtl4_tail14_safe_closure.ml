let ml_pipeline5 =
  [ "class:MTL4MachineLearningPipelineDescriptor"
  ; "class:MTL4MachineLearningPipelineReflection"
  ; "method:-[MTL4MachineLearningPipelineState label]"
  ; "property:MTL4MachineLearningPipelineState:label"
  ; "protocol:MTL4MachineLearningPipelineState" ]

let compute5 =
  [ "method:-[MTL4ComputeCommandEncoder buildAccelerationStructure:descriptor:scratchBuffer:]"
  ; "method:-[MTL4ComputeCommandEncoder copyFromTensor:sourceOrigin:sourceDimensions:toTensor:destinationOrigin:destinationDimensions:]"
  ; "method:-[MTL4ComputeCommandEncoder refitAccelerationStructure:descriptor:destination:scratchBuffer:]"
  ; "method:-[MTL4ComputeCommandEncoder refitAccelerationStructure:descriptor:destination:scratchBuffer:options:]"
  ; "method:-[MTL4ComputeCommandEncoder writeCompactedAccelerationStructureSize:toBuffer:]" ]

let ml_encoder4 =
  [ "method:-[MTL4MachineLearningCommandEncoder dispatchNetworkWithIntermediatesHeap:]"
  ; "method:-[MTL4MachineLearningCommandEncoder setArgumentTable:]"
  ; "method:-[MTL4MachineLearningCommandEncoder setPipelineState:]"
  ; "protocol:MTL4MachineLearningCommandEncoder" ]

let promotable_ids = ml_pipeline5 @ compute5 @ ml_encoder4

let validate () =
  if List.length ml_pipeline5 <> 5 || List.length compute5 <> 5
     || List.length ml_encoder4 <> 4
     || List.length (List.sort_uniq String.compare promotable_ids) <> 14
  then failwith "MTL4 ML/compute tail exact14 drift"

let () = validate ()
