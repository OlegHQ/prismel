type status = Promotable | Blocked

let compute_ids =
  Binding_metal4_manifest.ids
  |> List.filter (fun id -> String.starts_with ~prefix:"method:-[MTL4ComputeCommandEncoder " id)
  |> List.filter (fun id ->
       not (List.mem id
         [ "method:-[MTL4ComputeCommandEncoder buildAccelerationStructure:descriptor:scratchBuffer:]"
         ; "method:-[MTL4ComputeCommandEncoder copyFromTensor:sourceOrigin:sourceDimensions:toTensor:destinationOrigin:destinationDimensions:]"
         ; "method:-[MTL4ComputeCommandEncoder refitAccelerationStructure:descriptor:destination:scratchBuffer:]"
         ; "method:-[MTL4ComputeCommandEncoder refitAccelerationStructure:descriptor:destination:scratchBuffer:options:]"
         ; "method:-[MTL4ComputeCommandEncoder writeCompactedAccelerationStructureSize:toBuffer:]"
         ; "method:-[MTL4ComputeCommandEncoder dispatchThreads:threadsPerThreadgroup:]"
         ; "method:-[MTL4ComputeCommandEncoder setArgumentTable:]"
         ; "method:-[MTL4ComputeCommandEncoder setComputePipelineState:]"
         ; "method:-[MTL4ComputeCommandEncoder setThreadgroupMemoryLength:atIndex:]" ]))

let generic_ids =
  [ "method:-[MTL4CommandEncoder barrierAfterEncoderStages:beforeEncoderStages:visibilityOptions:]"
  ; "method:-[MTL4CommandEncoder barrierAfterStages:beforeQueueStages:visibilityOptions:]"
  ; "method:-[MTL4CommandEncoder insertDebugSignpost:]"
  ; "method:-[MTL4CommandEncoder popDebugGroup]"
  ; "method:-[MTL4CommandEncoder pushDebugGroup:]"
  ; "method:-[MTL4CommandEncoder updateFence:afterEncoderStages:]" ]

let residency_ids =
  [ "method:-[MTL4CommandQueue addResidencySets:count:]"
  ; "method:-[MTL4CommandQueue removeResidencySet:]"
  ; "method:-[MTL4CommandQueue removeResidencySets:count:]" ]

let counter_ids =
  [ "method:-[MTL4CounterHeap count]"
  ; "method:-[MTL4CounterHeap invalidateCounterRange:]"
  ; "method:-[MTL4CounterHeap label]"
  ; "method:-[MTL4CounterHeap resolveCounterRange:]"
  ; "method:-[MTL4CounterHeap setLabel:]"
  ; "method:-[MTL4CounterHeap type]"
  ; "method:-[MTL4CounterHeapDescriptor count]"
  ; "method:-[MTL4CounterHeapDescriptor setCount:]"
  ; "method:-[MTL4CounterHeapDescriptor setType:]"
  ; "method:-[MTL4CounterHeapDescriptor type]"
  ; "property:MTL4CounterHeap:count"
  ; "property:MTL4CounterHeap:label"
  ; "property:MTL4CounterHeap:type"
  ; "property:MTL4CounterHeapDescriptor:count"
  ; "property:MTL4CounterHeapDescriptor:type" ]

let callable_ids =
  List.sort_uniq String.compare (compute_ids @ generic_ids @ residency_ids @ counter_ids)

let blocked_ids =
  List.filter (fun id -> not (List.mem id callable_ids)) Binding_metal4_manifest.ids

let promotable_ids = callable_ids
let status id = if List.mem id promotable_ids then Promotable else Blocked

let validate () =
  if List.length compute_ids <> 27 || List.length generic_ids <> 6
     || List.length residency_ids <> 3 || List.length counter_ids <> 15
     || List.length callable_ids <> 51
     || List.length blocked_ids <> Binding_metal4_manifest.count - 51
     || List.exists (fun id -> not (List.mem id Binding_metal4_manifest.ids)) callable_ids
  then failwith "Metal4 exact callable safe reachability drift"

let () = validate ()
