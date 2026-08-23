type declaration={id:string;header:string;kind:string;owner:string option;name:string;signature:string}
type lane=Metadata|Mechanical|Handwritten_ownership
type entry={declaration:declaration;lane:lane}
let expected_count=190
let expected_digest="3c2848f1c1dc8b31de399cb502a444f30a672b1da00c07246989f0561dd0c2a4"
let contains text needle=let rec f i=i+String.length needle<=String.length text&&(String.sub text i(String.length needle)=needle||f(i+1))in f 0
let excluded_exact_ids=[] (* committed exact manifests currently intersect this header closure by zero *)
let selected d=String.length d.header>=10&&String.sub d.header 0 10="Metal/MTL4"&&d.header<>"Metal/MTL4AccelerationStructure.h"&&not(List.mem d.id excluded_exact_ids)
let classify d=if d.kind<>"method"&&d.kind<>"property"then Metadata else if List.exists(contains d.signature)["*";"id<";"NSArray";"NSString";"NSError";"instancetype";"dispatch_";"MTL4MachineLearningPipelineState";"MTL4ComputePipelineState";"MTL4RenderPipelineState";"MTL4FunctionDescriptor";"MTLFunction";"MTLBuffer";"MTLTexture";"MTLFence";"MTLHeap"]then Handwritten_ownership else Mechanical
let select ds=ds|>List.filter selected|>List.map(fun declaration->{declaration;lane=classify declaration})
let count lane es=List.fold_left(fun n e->if e.lane=lane then n+1 else n)0 es
let validate es=if List.length es<>expected_count then invalid_arg"mtl4 residual190 closure drift"else if List.length(List.sort_uniq String.compare(List.map(fun e->e.declaration.id)es))<>expected_count then invalid_arg"mtl4 residual duplicate"
