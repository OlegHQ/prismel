type package=Compute_binding|Render_draw|Reset|Render_binding|Pipeline|Type_metadata
type item={id:string;package:package;operation:string;tests:string list}
let callable_ids =
  [ "method:-[MTLIndirectComputeCommand setKernelBuffer:offset:attributeStride:atIndex:]"
  ; "method:-[MTLIndirectRenderCommand drawIndexedPatches:patchStart:patchCount:patchIndexBuffer:patchIndexBufferOffset:controlPointIndexBuffer:controlPointIndexBufferOffset:instanceCount:baseInstance:tessellationFactorBuffer:tessellationFactorBufferOffset:tessellationFactorBufferInstanceStride:]"
  ; "method:-[MTLIndirectRenderCommand drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:baseVertex:baseInstance:]"
  ; "method:-[MTLIndirectRenderCommand drawPatches:patchStart:patchCount:patchIndexBuffer:patchIndexBufferOffset:instanceCount:baseInstance:tessellationFactorBuffer:tessellationFactorBufferOffset:tessellationFactorBufferInstanceStride:]"
  ; "method:-[MTLIndirectRenderCommand drawPrimitives:vertexStart:vertexCount:instanceCount:baseInstance:]"
  ; "method:-[MTLIndirectRenderCommand reset]"
  ; "method:-[MTLIndirectRenderCommand setFragmentBuffer:offset:atIndex:]"
  ; "method:-[MTLIndirectRenderCommand setMeshBuffer:offset:atIndex:]"
  ; "method:-[MTLIndirectRenderCommand setObjectBuffer:offset:atIndex:]"
  ; "method:-[MTLIndirectRenderCommand setRenderPipelineState:]"
  ; "method:-[MTLIndirectRenderCommand setVertexBuffer:offset:atIndex:]"
  ; "method:-[MTLIndirectRenderCommand setVertexBuffer:offset:attributeStride:atIndex:]"
  ]
let contains s n=let l=String.length n in let rec f i=i+l<=String.length s&&(String.sub s i l=n||f(i+1))in f 0
let classify~kind id=let package,operation,tests=if kind="protocol"then Type_metadata,"Metal.Indirect command capability types",["public provenance"]else if contains id "MTLIndirectCompute"then Compute_binding,"Metal.Indirect_compute_command.set_kernel_buffer",["buffer range/alignment/index";"attribute stride"]else if contains id " draw"then Render_draw,"Metal.Indirect_render_command.draw",["primitive/index/patch cardinality";"buffer offsets and tessellation stride";"retention"]else if contains id " reset]"then Reset,"Metal.Indirect_render_command.reset",["command state transition";"retained resource release"]else if contains id "PipelineState"then Pipeline,"Metal.Indirect_render_command.set_pipeline",["same-device pipeline";"indirect-command capability"]else Render_binding,"Metal.Indirect_render_command.set_*_buffer",["same-device buffer";"offset/stride/index bounds";"replacement retention"]in{id;package;operation;tests}
let validate items=let count p=List.length(List.filter(fun x->x.package=p)items)in if List.length items<>14||List.map count[Compute_binding;Render_draw;Reset;Render_binding;Pipeline;Type_metadata]<>[1;4;1;5;1;2]||List.exists(fun x->x.operation=""||x.tests=[])items then failwith"IndirectCommand14 tail drift"
