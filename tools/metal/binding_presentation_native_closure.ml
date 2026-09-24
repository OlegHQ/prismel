let final_getters =
  [ "method:-[MTLRenderPassDescriptor defaultRasterSampleCount]"
  ; "method:-[MTLRenderPassDescriptor renderTargetArrayLength]"
  ; "method:-[MTLRenderPassDescriptor renderTargetHeight]"
  ; "method:-[MTLRenderPassDescriptor renderTargetWidth]" ]
let noncallable_metadata = [ "record:_CAMetalLayerPrivate" ]
let callable_count = 81
let validate () =
  if List.length final_getters <> 4 || List.length noncallable_metadata <> 1 ||
     callable_count + List.length Binding_presentation_public_audit.safe_reachable <> 124
  then failwith "presentation native closure drift";
  if List.sort_uniq String.compare
       (Binding_presentation_public_audit.safe_reachable
        @ Binding_presentation_advanced_closure.callable_ids
        @ Binding_presentation_layer_closure.callable_ids
        @ Binding_presentation_command_closure.callable_ids
        @ Binding_presentation_graph_tail_closure.callable_ids
        @ Binding_presentation_descriptor_tail_closure.callable_ids
        @ final_getters @ noncallable_metadata)
     <> List.sort_uniq String.compare Binding_presentation_manifest.ids
  then failwith "presentation 124 callable + 1 metadata set inequality"
let () = validate ()
