let initial_ownership_ids=
 ["method:-[MTL4CommandBuffer beginCommandBufferWithAllocator:options:]";
  "method:-[MTL4CommandQueue waitForEvent:value:]";
  "method:-[MTL4CommandEncoder waitForFence:beforeEncoderStages:]";
  "method:-[MTL4ComputeCommandEncoder copyFromBuffer:sourceOffset:toBuffer:destinationOffset:size:]";
  "method:-[MTL4CommandQueue addResidencySet:]";
  "method:-[MTL4CommandQueue signalDrawable:]";
  "method:-[MTL4CommandQueue waitForDrawable:]";
  "method:-[MTL4Compiler newRenderPipelineStateWithDescriptor:compilerTaskOptions:completionHandler:]"]
let contains s n=let l=String.length n in let rec f i=i+l<=String.length s&&(String.sub s i l=n||f(i+1))in f 0
let compute_ownership_ids=Binding_metal4_audit.items|>List.filter_map(fun (x:Binding_metal4_audit.item)->match x.lane with Binding_metal4_audit.Handwritten_lifecycle when contains x.id "method:-[MTL4ComputeCommandEncoder "->Some x.id|_->None)
let covered_ownership_ids=List.sort_uniq String.compare(initial_ownership_ids@compute_ownership_ids)
let all_ownership_ids=Binding_metal4_audit.items|>List.filter_map(fun (x:Binding_metal4_audit.item)->match x.lane with Binding_metal4_audit.Handwritten_lifecycle->Some x.id|_->None)
let remaining_ownership_ids=all_ownership_ids|>List.filter(fun id->not(List.mem id covered_ownership_ids))
