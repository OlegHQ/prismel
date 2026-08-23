type declaration={id:string;header:string;kind:string;owner:string option;name:string;signature:string}
type lane=Metadata|Mechanical|Handwritten_ownership
type entry={declaration:declaration;lane:lane}
let expected_count=113
let expected_digest="ca20299ddb844da5bd51c664b71b1d33e21491f8db75346144d170a96f098a0c"
let excluded_owners=["MTLMeshRenderPipelineDescriptor";"MTLTileRenderPipelineDescriptor";"MTLPipelineBufferDescriptor";"MTLPipelineBufferDescriptorArray";"MTLRenderPipelineColorAttachmentDescriptor";"MTLRenderPipelineColorAttachmentDescriptorArray"]
let acceleration_tokens=["AccelerationStructure";"IntersectionFunctionTable";"VisibleFunctionTable";"FunctionHandle"]
let contains text needle=let rec f i=i+String.length needle<=String.length text&&(String.sub text i(String.length needle)=needle||f(i+1))in f 0
let selected d=
  let header=d.header="Metal/MTLRenderPipeline.h"||d.header="Metal/MTLComputePipeline.h" in
  let owner=Option.value d.owner ~default:d.name in
  header && not(List.mem owner excluded_owners) &&
  (d.kind<>"method" || not(List.exists(fun x->contains d.name x||contains d.signature x)acceleration_tokens))
let classify d=if d.kind<>"method"&&d.kind<>"property"then Metadata
 else if List.exists(contains d.signature)["*";"id<";"NSArray";"NSString";"NSError";"instancetype";"MTL4PipelineDescriptor";"MTLRenderPipelineFunctionsDescriptor";"MTLStageInputOutputDescriptor";"MTLVertexDescriptor";"MTLLinkedFunctions";"MTLPipelineBufferDescriptorArray"]then Handwritten_ownership else Mechanical
let select ds=ds|>List.filter selected|>List.map(fun declaration->{declaration;lane=classify declaration})
let count lane es=List.fold_left(fun n e->if e.lane=lane then n+1 else n)0 es
let validate es=if List.length es<>expected_count then invalid_arg"pipeline113 closure drift" else
 if List.length(List.sort_uniq String.compare(List.map(fun e->e.declaration.id)es))<>expected_count then invalid_arg"pipeline113 duplicate"
