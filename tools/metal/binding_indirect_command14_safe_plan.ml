let ids = Binding_indirect_command14_native_closure.ids

let already_safe =
  [ "method:-[MTLIndirectRenderCommand drawPrimitives:vertexStart:vertexCount:instanceCount:baseInstance:]"
  ; "method:-[MTLIndirectRenderCommand reset]"
  ; "method:-[MTLIndirectRenderCommand setFragmentBuffer:offset:atIndex:]"
  ; "method:-[MTLIndirectRenderCommand setRenderPipelineState:]"
  ; "method:-[MTLIndirectRenderCommand setVertexBuffer:offset:atIndex:]"
  ; "protocol:MTLIndirectComputeCommand"
  ; "protocol:MTLIndirectRenderCommand" ]

let pending_safe = List.filter (fun id -> not (List.mem id already_safe)) ids

let validate () =
  if List.length ids <> 14 || List.length already_safe <> 7 ||
     List.length pending_safe <> 7 ||
     List.length (List.sort_uniq String.compare ids) <> 14 then
    invalid_arg "IndirectCommand14 safe partition drift"
