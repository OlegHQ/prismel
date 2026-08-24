let ownership_effect_ids =
  [ "method:-[MTLAttributeDescriptorArray objectAtIndexedSubscript:]"
  ; "method:-[MTLAttributeDescriptorArray setObject:atIndexedSubscript:]"
  ; "method:-[MTLStageInputOutputDescriptor attributes]"
  ; "method:-[MTLStageInputOutputDescriptor layouts]"
  ; "method:-[MTLStageInputOutputDescriptor reset]"
  ; "property:MTLStageInputOutputDescriptor:attributes"
  ; "property:MTLStageInputOutputDescriptor:layouts" ]

let metadata_ids =
  [ "class:MTLAttributeDescriptor"
  ; "class:MTLAttributeDescriptorArray"
  ; "class:MTLStageInputOutputDescriptor" ]

let () =
  let ids = ownership_effect_ids @ metadata_ids in
  if List.length ownership_effect_ids <> 7
     || List.length metadata_ids <> 3
     || List.length (List.sort_uniq String.compare ids) <> 10
  then invalid_arg "StageInputOutputDescriptor10 native closure drift"
