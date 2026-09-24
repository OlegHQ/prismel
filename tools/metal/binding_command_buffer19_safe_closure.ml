let callable_ids =
  [ "class:MTLCommandBufferDescriptor"
  ; "method:-[MTLCommandBufferDescriptor errorOptions]"
  ; "method:-[MTLCommandBufferDescriptor logState]"
  ; "method:-[MTLCommandBufferDescriptor retainedReferences]"
  ; "method:-[MTLCommandBufferDescriptor setErrorOptions:]"
  ; "method:-[MTLCommandBufferDescriptor setLogState:]"
  ; "method:-[MTLCommandBufferDescriptor setRetainedReferences:]"
  ; "method:-[MTLCommandBufferEncoderInfo debugSignposts]"
  ; "method:-[MTLCommandBufferEncoderInfo errorState]"
  ; "method:-[MTLCommandBufferEncoderInfo label]"
  ; "property:MTLCommandBufferDescriptor:errorOptions"
  ; "property:MTLCommandBufferDescriptor:logState"
  ; "property:MTLCommandBufferDescriptor:retainedReferences"
  ; "property:MTLCommandBufferEncoderInfo:debugSignposts"
  ; "property:MTLCommandBufferEncoderInfo:errorState"
  ; "property:MTLCommandBufferEncoderInfo:label"
  ; "protocol:MTLCommandBufferEncoderInfo"
  ; "protocol:MTLLogContainer"
  ; "typedef:MTLCommandBufferHandler" ]

let promotable_ids = callable_ids

