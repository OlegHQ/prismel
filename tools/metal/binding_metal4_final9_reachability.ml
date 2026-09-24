type status = Promotable | Native_pending_safe
let queue_feedback_ids =
  [ "property:MTL4CommandQueueDescriptor:feedbackQueue"
  ; "method:-[MTL4CommandQueueDescriptor feedbackQueue]"
  ; "method:-[MTL4CommandQueueDescriptor setFeedbackQueue:]"
  ; "property:MTL4CommitFeedback:GPUStartTime"
  ; "method:-[MTL4CommitFeedback GPUStartTime]"
  ; "property:MTL4CommitFeedback:GPUEndTime"
  ; "method:-[MTL4CommitFeedback GPUEndTime]" ]
let specialization_ids =
  [ "method:-[MTL4Compiler newRenderPipelineStateBySpecializationWithDescriptor:pipeline:error:]"
  ; "method:-[MTL4Compiler newRenderPipelineStateBySpecializationWithDescriptor:pipeline:completionHandler:]" ]
let promotable_ids=queue_feedback_ids
let items = List.map (fun id -> id, Promotable) queue_feedback_ids @ List.map(fun id->id,Native_pending_safe)specialization_ids
let validate () =
  if List.length queue_feedback_ids <> 7 || List.length specialization_ids <> 2
     || List.length (List.sort_uniq String.compare (queue_feedback_ids @ specialization_ids)) <> 9
  then failwith "Metal4 final9 reachability drift"
let () = validate ()
