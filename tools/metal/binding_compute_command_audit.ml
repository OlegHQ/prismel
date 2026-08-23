type lane=Mechanical_value|Handwritten_command
type item={id:string;lane:lane}
let contains s n=let l=String.length n in let rec f i=i+l<=String.length s&&(String.sub s i l=n||f(i+1))in f 0
let scalar=[":dispatchType";":endOfEncoderSampleIndex";":startOfEncoderSampleIndex";
 ":requiredThreadsPerThreadgroup";":gpuResourceID";":shaderValidation";":supportIndirectCommandBuffers";
 "setDispatchType:";"setEndOfEncoderSampleIndex:";"setStartOfEncoderSampleIndex:";
 "setRequiredThreadsPerThreadgroup:";"setShaderValidation:";"setSupportIndirectCommandBuffers:"]
let mechanical id=String.starts_with~prefix:"enum-case:"id||List.exists(contains id)scalar
let items=List.map(fun id->{id;lane=if mechanical id then Mechanical_value else Handwritten_command})Binding_compute_command_manifest.ids
let count lane=List.fold_left(fun n x->if x.lane=lane then n+1 else n)0 items
