type status = Pending_safe | Blocked
let property owner name setter=["property:"^owner^":"^name;"method:-["^owner^" "^name^"]";"method:-["^owner^" "^setter^":]"]
let ml_ids =
  [ "method:-[MTL4MachineLearningPipelineDescriptor inputDimensionsAtBufferIndex:]"; "method:-[MTL4MachineLearningPipelineDescriptor reset]"; "method:-[MTL4MachineLearningPipelineDescriptor setInputDimensions:atBufferIndex:]"; "method:-[MTL4MachineLearningPipelineDescriptor setInputDimensions:withRange:]"
  ; "method:-[MTL4Compiler newMachineLearningPipelineStateWithDescriptor:error:]"
  ; "method:-[MTL4MachineLearningPipelineState device]"; "property:MTL4MachineLearningPipelineState:device"
  ; "method:-[MTL4MachineLearningPipelineState intermediatesHeapSize]"; "property:MTL4MachineLearningPipelineState:intermediatesHeapSize"
  ; "method:-[MTL4MachineLearningPipelineState reflection]"; "property:MTL4MachineLearningPipelineState:reflection"
  ; "method:-[MTL4MachineLearningPipelineReflection bindings]"; "property:MTL4MachineLearningPipelineReflection:bindings" ] @
  property "MTL4MachineLearningPipelineDescriptor" "label" "setLabel" @
  property "MTL4MachineLearningPipelineDescriptor" "machineLearningFunctionDescriptor" "setMachineLearningFunctionDescriptor"
let specialized_ids=List.concat[property "MTL4SpecializedFunctionDescriptor" "functionDescriptor" "setFunctionDescriptor";property "MTL4SpecializedFunctionDescriptor" "specializedName" "setSpecializedName";property "MTL4SpecializedFunctionDescriptor" "constantValues" "setConstantValues"]
let stitched_ids=["property:MTL4StitchedFunctionDescriptor:functionDescriptors";"method:-[MTL4StitchedFunctionDescriptor functionDescriptors]";"method:-[MTL4StitchedFunctionDescriptor setFunctionDescriptors:]";"method:-[MTL4StitchedFunctionDescriptor functionGraph]"]
let pending_ids=List.sort_uniq String.compare(ml_ids@specialized_ids@stitched_ids)
let blocked_stitched_graph_ids=["property:MTL4StitchedFunctionDescriptor:functionGraph";"method:-[MTL4StitchedFunctionDescriptor setFunctionGraph:]"]
let status id=if List.mem id pending_ids then Pending_safe else Blocked
let validate()=if List.length ml_ids<>19||List.length specialized_ids<>9||List.length stitched_ids<>4||List.length pending_ids<>32||List.length blocked_stitched_graph_ids<>2 then failwith"Metal4 native32 reachability drift"
let ()=validate()
