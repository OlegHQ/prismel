type item = { id : string; public_type : string }

let items =
  [ { id = "class:MTLAttributeDescriptor"; public_type = "Binding_stage_input_output_safe_package.attribute" }
  ; { id = "class:MTLAttributeDescriptorArray"; public_type = "Binding_stage_input_output_safe_package.attribute option array" }
  ; { id = "class:MTLStageInputOutputDescriptor"; public_type = "Binding_stage_input_output_safe_package.t" }
  ; { id = "class:MTLComputePassDescriptor"; public_type = "Binding_compute_pass_safe_package.descriptor" }
  ; { id = "class:MTLComputePassSampleBufferAttachmentDescriptor"; public_type = "Binding_compute_pass_safe_package.attachment" }
  ; { id = "class:MTLComputePassSampleBufferAttachmentDescriptorArray"; public_type = "Binding_compute_pass_safe_package.attachment option array" } ]

let promotable_ids = List.map (fun item -> item.id) items

let validate () =
  if List.length items <> 6
     || List.length (List.sort_uniq String.compare promotable_ids) <> 6
     || List.exists (fun item -> item.public_type = "") items
  then failwith "StageInputOutput/ComputePass residual exact6 drift"
