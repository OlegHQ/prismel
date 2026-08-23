type declaration = { id:string; kind:string; owner:string option; name:string; signature:string }
type lane = Metadata | Mechanical | Handwritten_ownership
type entry = { declaration:declaration; lane:lane }
let header = "Metal/MTLDevice.h"
let expected_count = 103
let expected_digest = "9f666df70c672fc3c6ff3ed267bc09e575e1f9e4673aed76058e6aac5d044961"
let contains text needle =
  let rec loop i=i+String.length needle<=String.length text &&
    (String.sub text i (String.length needle)=needle || loop(i+1)) in loop 0
let mechanical signature =
  not (List.exists (contains signature)
    ["*";"id<";"NSArray";"Handler";"dispatch_data_t";"MTLRegion";
     "MTLSamplePosition";"MTLTimestamp";"MTLAccelerationStructureSizes";
     "MTLSizeAndAlign"])
let classify declaration =
  if declaration.kind<>"method" && declaration.kind<>"property" then Metadata
  else if mechanical declaration.signature then Mechanical else Handwritten_ownership
let select declarations =
  declarations |> List.map(fun declaration->{declaration;lane=classify declaration})
let count lane entries = List.fold_left(fun n e->if e.lane=lane then n+1 else n)0 entries
let validate entries =
  if List.length entries<>expected_count then invalid_arg "MTLDevice.h exact closure drift";
  let ids=List.map(fun e->e.declaration.id)entries in
  if List.length(List.sort_uniq String.compare ids)<>expected_count then
    invalid_arg "MTLDevice.h duplicate IDs"
