type status = Native_pending_safe | Awaiting_callback_bridge
let queue_feedback_ids =
  [ "property:MTL4CommandQueueDescriptor:feedbackQueue"
  ; "method:-[MTL4CommandQueueDescriptor feedbackQueue]"
  ; "method:-[MTL4CommandQueueDescriptor setFeedbackQueue:]"
  ; "property:MTL4CommitFeedback:GPUStartTime"
  ; "method:-[MTL4CommitFeedback GPUStartTime]"
  ; "property:MTL4CommitFeedback:GPUEndTime"
  ; "method:-[MTL4CommitFeedback GPUEndTime]" ]
let callback_ids =
  [ "method:-[MTL4Compiler newMachineLearningPipelineStateWithDescriptor:completionHandler:]"
  ; "method:-[MTL4Compiler newRenderPipelineStateBySpecializationWithDescriptor:pipeline:completionHandler:]" ]
let items = List.map (fun id -> id, Native_pending_safe) queue_feedback_ids @ List.map (fun id -> id, Awaiting_callback_bridge) callback_ids
let validate () =
  if List.length queue_feedback_ids <> 7 || List.length callback_ids <> 2
     || List.length (List.sort_uniq String.compare (queue_feedback_ids @ callback_ids)) <> 9
  then failwith "Metal4 final9 reachability drift"
let () = validate ()
