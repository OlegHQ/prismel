let archive_ids =
  [ "method:-[MTL4Archive newComputePipelineStateWithDescriptor:dynamicLinkingDescriptor:error:]"
  ; "method:-[MTL4Archive newComputePipelineStateWithDescriptor:error:]"
  ; "method:-[MTL4Archive newRenderPipelineStateWithDescriptor:dynamicLinkingDescriptor:error:]"
  ; "method:-[MTL4Archive newRenderPipelineStateWithDescriptor:error:]" ]
let remaining_promotable_ids=Binding_metal4_final9_reachability.specialization_ids@archive_ids
let promoted_ids = Binding_metal4_native32_reachability.promotable_ids @ Binding_metal4_final9_reachability.promotable_ids@remaining_promotable_ids
let pending_ids=[]
let archive_noncallable_ids=[]
let validate () =
  if List.length remaining_promotable_ids<>6||List.length promoted_ids <> 45 || pending_ids<>[]||archive_noncallable_ids<>[]
     || List.length (List.sort_uniq String.compare promoted_ids)<>45
  then failwith "Metal4 combined pending41 reachability drift"
let () = validate ()
