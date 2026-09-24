let ids =
  [ "method:-[MTLIndirectCommandBuffer gpuResourceID]"
  ; "method:-[MTLIndirectCommandBuffer indirectRenderCommandAtIndex:]"
  ; "property:MTLIndirectCommandBuffer:gpuResourceID"
  ; "protocol:MTLIndirectCommandBuffer" ]

let validate () =
  if List.length ids <> 4 || List.length (List.sort_uniq String.compare ids) <> 4
  then invalid_arg "IndirectCommandBuffer4 exact closure drift"
