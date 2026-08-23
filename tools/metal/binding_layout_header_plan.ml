type declaration={id:string;kind:string;owner:string option;name:string;signature:string}
type lane=Metadata|Mechanical|Handwritten_ownership
type entry={declaration:declaration;lane:lane}
let headers=["Metal/MTLTensor.h";"Metal/MTLRasterizationRate.h"]
let expected_count=102
let expected_digest="64ffa1fb0bc770c38e2da86d3fb6f02b1c4b29d30306cdd220cbec7432eb97e6"
let contains text needle=let rec f i=i+String.length needle<=String.length text&&(String.sub text i(String.length needle)=needle||f(i+1))in f 0
let classify d=if d.kind<>"method"&&d.kind<>"property"then Metadata
 else if List.exists(contains d.signature)["*";"id<";"NSString";"NSNumber";"instancetype";"MTLSizeAndAlign"]then Handwritten_ownership else Mechanical
let select ds=List.map(fun declaration->{declaration;lane=classify declaration})ds
let count lane es=List.fold_left(fun n e->if e.lane=lane then n+1 else n)0 es
let validate es=if List.length es<>expected_count then invalid_arg"layout102 closure drift"else
 if List.length(List.sort_uniq String.compare(List.map(fun e->e.declaration.id)es))<>expected_count then invalid_arg"layout102 duplicate"
