type lane=Mechanical_value|Handwritten_command
type item={id:string;lane:lane}
let mechanical_names=
  [ "dispatchThreadsPerTile:"; "drawMeshThreadgroups:threadsPerObjectThreadgroup:threadsPerMeshThreadgroup:"
  ; "drawMeshThreads:threadsPerObjectThreadgroup:threadsPerMeshThreadgroup:"
  ; "drawPrimitives:vertexStart:vertexCount:"
  ; "drawPrimitives:vertexStart:vertexCount:instanceCount:baseInstance:"
  ; "memoryBarrierWithScope:afterStages:beforeStages:"; "setDepthClipMode:"
  ; "setDepthStoreAction:"; "setDepthStoreActionOptions:"; "setDepthTestMinBound:maxBound:"
  ; "setFragmentBufferOffset:atIndex:"; "setMeshBufferOffset:atIndex:"
  ; "setObjectBufferOffset:atIndex:"; "setObjectThreadgroupMemoryLength:atIndex:"
  ; "setStencilReferenceValue:"; "setStencilStoreAction:"; "setStencilStoreActionOptions:"
  ; "setTessellationFactorScale:"; "setThreadgroupMemoryLength:offset:atIndex:"
  ; "setTileBufferOffset:atIndex:"; "setVertexBufferOffset:atIndex:"
  ; "setVertexBufferOffset:attributeStride:atIndex:"; "textureBarrier" ]
let method_name id =
  let prefix="method:-[MTLRenderCommandEncoder " in
  if String.starts_with ~prefix id then String.sub id (String.length prefix) (String.length id-String.length prefix-1)
  else ""
let items=List.map(fun id->{id;lane=if List.mem(method_name id)mechanical_names then Mechanical_value else Handwritten_command})Binding_render_encoder_manifest.ids
let count lane=List.fold_left(fun n item->if item.lane=lane then n+1 else n)0 items
let invariants=
  [ "encoder and every resource belong to one live command buffer/device"
  ; "buffer ranges, indirect argument layouts, indices, and alignments are checked"
  ; "array counts match OCaml array lengths and never expose unsafe_unretained pointers"
  ; "bound resources remain retained through command completion"
  ; "stage/pipeline capability gates precede selector entry"
  ; "encoder state rejects calls after endEncoding or command commit"
  ; "draw and dispatch dimensions are positive and within device limits"
  ; "failure leaves encoder retention/state unchanged" ]
