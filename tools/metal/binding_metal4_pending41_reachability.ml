let promoted_ids = Binding_metal4_native32_reachability.promotable_ids
let pending_ids = List.sort_uniq String.compare
  (Binding_metal4_final9_reachability.queue_feedback_ids @
   Binding_metal4_final9_reachability.specialization_ids)
let archive_noncallable_ids =
  [ "method:-[MTL4Archive newComputePipelineStateWithDescriptor:dynamicLinkingDescriptor:error:]"
  ; "method:-[MTL4Archive newComputePipelineStateWithDescriptor:error:]"
  ; "method:-[MTL4Archive newRenderPipelineStateWithDescriptor:dynamicLinkingDescriptor:error:]"
  ; "method:-[MTL4Archive newRenderPipelineStateWithDescriptor:error:]" ]
let validate () =
  if List.length promoted_ids <> 32 || List.length pending_ids <> 9 || List.length archive_noncallable_ids <> 4
     || List.length (List.sort_uniq String.compare (promoted_ids@pending_ids))<>41
     || List.exists (fun id -> List.mem id pending_ids||List.mem id promoted_ids) archive_noncallable_ids
  then failwith "Metal4 combined pending41 reachability drift"
let () = validate ()
